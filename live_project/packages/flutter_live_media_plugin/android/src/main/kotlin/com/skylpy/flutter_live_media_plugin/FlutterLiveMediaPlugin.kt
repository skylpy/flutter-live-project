package com.skylpy.flutter_live_media_plugin

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.SurfaceView
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.pedro.common.ConnectChecker
import com.pedro.library.rtmp.RtmpStream
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

private const val PLAYER_VIEW_TYPE = "flutter_live_media_player_view"
private const val PUBLISHER_VIEW_TYPE = "flutter_live_media_publisher_view"
private const val LOG_TAG = "FlutterLiveMedia"
private const val MAX_RECONNECT_ATTEMPTS = 3
private const val FIRST_RECONNECT_DELAY_MILLIS = 1_000L

/**
 * Flutter 插件入口。
 *
 * Flutter 引擎加载插件后会调用 [onAttachedToEngine]。这里完成两件事：
 * 1. 把 Pigeon HostApi 绑定到 Android 实现；
 * 2. 注册 PlatformView，让 Dart 的 AndroidView 能找到原生 PlayerView。
 *
 * 插件入口不直接写业务页面逻辑，这样同一个插件可以被多个 Flutter App 复用。
 */
class FlutterLiveMediaPlugin : FlutterPlugin {
    private var mediaEngine: AndroidLiveMediaEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // 使用 applicationContext 创建播放器，避免把 Activity 生命周期错误地
        // 绑定到播放器，造成旋转屏幕或页面重建时的资源泄漏。
        val engine = AndroidLiveMediaEngine(binding.applicationContext, binding.binaryMessenger)
        mediaEngine = engine
        LiveMediaHostApi.setUp(binding.binaryMessenger, engine)
        // 这个字符串必须与 Dart AndroidView 的 viewType 完全一致。
        binding.platformViewRegistry.registerViewFactory(
            PLAYER_VIEW_TYPE,
            AndroidLiveMediaPlayerViewFactory(engine.player),
        )
        // 主播端使用独立 SurfaceView。它与观众端 PlayerView 分开，避免在同一个
        // PlatformView 中混合 ExoPlayer 渲染和 Camera2 采集。
        binding.platformViewRegistry.registerViewFactory(
            PUBLISHER_VIEW_TYPE,
            AndroidLiveMediaPublisherViewFactory(engine),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // FlutterEngine 销毁时解除消息处理并释放 ExoPlayer、Handler 和协程。
        LiveMediaHostApi.setUp(binding.binaryMessenger, null)
        mediaEngine?.dispose()
        mediaEngine = null
    }
}

private class AndroidLiveMediaEngine(
    context: Context,
    messenger: BinaryMessenger,
) : LiveMediaHostApi {
    private val applicationContext = context.applicationContext

    // ExoPlayer 负责真正的媒体解析和播放；Flutter 只通过接口调用它。
    val player: ExoPlayer = ExoPlayer.Builder(applicationContext).build()

    // HLS 的分片请求由 DefaultDataSource 统一发出。把 DataSourceFactory 保存下来，
    // 重连时可以用完全相同的网络配置重新创建 HlsMediaSource，而不是复制一套请求代码。
    private val hlsMediaSourceFactory = HlsMediaSource.Factory(
        DefaultDataSource.Factory(applicationContext),
    )

    private val eventApi = LiveMediaFlutterApi(messenger)
    private val eventScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentUrl: String? = null
    private var reconnectAttempt = 0
    private var reconnectRunnable: Runnable? = null

    // RootEncoder 只负责主播端推流；不要复用 ExoPlayer 的 currentUrl 或 stop()。
    private var pushStream: RtmpStream? = null
    private var publisherSurface: SurfaceView? = null
    private var previewRequested = false

    init {
        // Player.Listener 是 ExoPlayer 的状态出口。这里只转换状态并发送统一事件，
        // 不把 ExoPlayer 类型泄露给 Flutter 层。
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        Log.d(LOG_TAG, "HLS playback state: BUFFERING")
                        emit(LiveMediaEventType.BUFFERING, "播放器缓冲中")
                    }
                    Player.STATE_READY -> {
                        // READY 表示当前媒体已经重新准备好。重连成功后必须清零次数，
                        // 否则下一次独立的网络故障会错误地直接进入“次数耗尽”。
                        cancelReconnect()
                        reconnectAttempt = 0
                        Log.i(LOG_TAG, "HLS playback state: READY, url=$currentUrl")
                        emit(LiveMediaEventType.PLAYING, "播放器播放中")
                    }
                    Player.STATE_ENDED -> {
                        Log.i(LOG_TAG, "HLS playback state: ENDED")
                        emit(LiveMediaEventType.COMPLETED, "播放已完成")
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                // 先通知当前错误，再安排指数退避重连；这样 UI 可以立即显示网络异常。
                Log.w(LOG_TAG, "HLS playback error: ${error.errorCodeName}", error)
                emit(LiveMediaEventType.ERROR, error.message ?: error.errorCodeName)
                scheduleReconnect()
            }
        })
    }

    override suspend fun initialize(configuration: LiveEngineConfiguration): Boolean {
        // 播放器在插件挂载时已创建，初始化方法仍保留是为了遵守跨平台 LiveEngine
        // 生命周期，未来可在这里应用硬件加速、音频焦点等配置。
        emit(LiveMediaEventType.INITIALIZED, "Android 媒体引擎已初始化")
        return true
    }

    override suspend fun play(url: String): Boolean {
        // 当前阶段只接受 HTTP/HTTPS。RTMP、HTTP-FLV、WebRTC 等协议必须在后续
        // 引入相应 MediaSource 或 SDK 后再开放，避免把协议实现混进 Flutter UI。
        val normalizedUrl = url.trim()
        val scheme = Uri.parse(normalizedUrl).scheme?.lowercase()
        if (normalizedUrl.isEmpty() || scheme !in setOf("http", "https")) {
            emit(LiveMediaEventType.ERROR, "当前仅支持 HTTP/HTTPS 播放地址")
            return false
        }

        // 新播放请求代表用户切换了房间，必须取消旧房间的重连任务并重置次数。
        cancelReconnect()
        reconnectAttempt = 0
        currentUrl = normalizedUrl
        Log.i(LOG_TAG, "HLS play requested: $normalizedUrl")
        // 这里明确创建 HlsMediaSource，而不是依赖默认 MediaSourceFactory 猜格式。
        // 这样带查询参数、没有 .m3u8 后缀的直播地址也能按 HLS 解析。
        player.setMediaSource(createHlsMediaSource(normalizedUrl), true)
        // prepare 触发清单和分片解析；playWhenReady 表示 READY 后自动开始播放。
        // 真正的 playing 状态仍然由 Player.Listener 回调给 Flutter。
        player.prepare()
        player.playWhenReady = true
        return true
    }

    override suspend fun stop(): Boolean {
        // 清理当前 URL 很重要：它会阻止已经排队的重连任务重新启动旧直播间。
        cancelReconnect()
        reconnectAttempt = 0
        currentUrl = null
        Log.i(LOG_TAG, "HLS stop requested")
        player.stop()
        player.clearMediaItems()
        emit(LiveMediaEventType.STOPPED, "Android 播放器已停止")
        return true
    }

    override suspend fun startPreview(): Boolean {
        // 摄像头采集需要先经过 Android 运行时权限检查。权限由 Flutter 页面申请，
        // 这里只负责创建编码器并把画面输出到主播 PlatformView。
        val stream = ensurePushStream() ?: return false
        previewRequested = true
        if (!stream.isOnPreview) {
            publisherSurface?.let { stream.startPreview(it) }
        }
        emit(LiveMediaEventType.PREVIEW_STARTED, "Android 摄像头预览已启动")
        return true
    }

    override suspend fun startPush(url: String): Boolean {
        val normalizedUrl = url.trim()
        val scheme = Uri.parse(normalizedUrl).scheme?.lowercase()
        if (normalizedUrl.isEmpty() || scheme !in setOf("rtmp", "rtmps")) {
            emit(LiveMediaEventType.ERROR, "当前仅支持 RTMP/RTMPS 推流地址")
            return false
        }

        val stream = ensurePushStream() ?: return false
        if (!stream.isOnPreview) {
            publisherSurface?.let { stream.startPreview(it) }
        }
        previewRequested = true
        emit(LiveMediaEventType.PUSH_CONNECTING, "正在连接 RTMP 推流服务器")
        return runCatching {
            stream.startStream(normalizedUrl)
            true
        }.getOrElse { error ->
            Log.e(LOG_TAG, "RTMP push start failed", error)
            emit(LiveMediaEventType.ERROR, error.message ?: "RTMP 推流启动失败")
            false
        }
    }

    override suspend fun stopPush(): Boolean {
        // 先停网络推流，再停预览；否则摄像头仍会被编码器占用，下一次开播可能
        // 拿不到 Camera2 资源。这里不影响观众端 ExoPlayer。
        pushStream?.let { stream ->
            runCatching { stream.stopStream() }
            runCatching { stream.stopPreview() }
        }
        previewRequested = false
        emit(LiveMediaEventType.PUSH_STOPPED, "Android 推流已停止")
        return true
    }

    private fun scheduleReconnect() {
        val url = currentUrl ?: return
        // 同一次播放错误可能触发多个底层回调，已有任务时不能重复排队，
        // 否则一个错误会同时启动多个播放器请求。
        if (reconnectRunnable != null) return
        if (reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) {
            emit(LiveMediaEventType.ERROR, "播放器重连次数已耗尽")
            return
        }

        reconnectAttempt += 1
        val attempt = reconnectAttempt
        // 1s、2s、4s 的指数退避，避免网络故障时高频重试压垮服务端。
        val delayMillis = FIRST_RECONNECT_DELAY_MILLIS shl (attempt - 1)
        Log.i(LOG_TAG, "HLS reconnect scheduled: attempt=$attempt delayMs=$delayMillis")
        emit(
            LiveMediaEventType.RECONNECTING,
            "播放器将在 ${delayMillis / 1000} 秒后重连",
            attempt,
        )

        val runnable = Runnable {
            // 用户如果已经切换房间或停止播放，旧任务即使执行也不能重新播放。
            if (currentUrl != url) return@Runnable
            reconnectRunnable = null
            Log.i(LOG_TAG, "HLS reconnect started: attempt=$attempt")
            // 重连要重新创建 MediaSource，确保清单和分片请求从当前网络状态重新开始。
            player.setMediaSource(createHlsMediaSource(url), true)
            player.prepare()
            player.playWhenReady = true
        }
        reconnectRunnable = runnable
        mainHandler.postDelayed(runnable, delayMillis)
    }

    private fun cancelReconnect() {
        reconnectRunnable?.let(mainHandler::removeCallbacks)
        reconnectRunnable = null
    }

    private fun createHlsMediaSource(url: String): HlsMediaSource {
        // 显式声明 MIME 类型能让 Media3 在 URL 没有标准后缀时仍按 HLS 处理。
        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMimeType(MimeTypes.APPLICATION_M3U8)
            .build()
        return hlsMediaSourceFactory.createMediaSource(mediaItem)
    }

    private fun ensurePushStream(): RtmpStream? {
        pushStream?.let { return it }
        return runCatching {
            RtmpStream(context = applicationContext, connectChecker = PushConnectChecker())
                .also { stream ->
                    // 720p/30fps/1.2Mbps 是 MVP 的保守默认值，后续再根据设备能力和
                    // 弱网策略动态调整；prepare* 返回 false 时不能启动推流。
                    // SRS 的 HLS 切片会在关键帧处切开。这里使用六参数重载，显式
                    // 设置 2 秒关键帧间隔，让不同 Android 编码器都遵守直播切片
                    // 所需的 GOP 粒度，避免观众端等待很长时间才出现第一帧。
                    val videoReady = stream.prepareVideo(720, 1280, 1_200_000, 30, 0, 2)
                    // RootEncoder 的参数顺序是 sampleRate、stereo、bitrate；不能
                    // 按常见的 bitrate、stereo、sampleRate 顺序传递，否则会生成
                    // 64000Hz AAC，部分 Android/Media3 解码器会拒绝这种音频流。
                    val audioReady = stream.prepareAudio(44_100, true, 64_000)
                    if (!videoReady || !audioReady) {
                        stream.release()
                        throw IllegalStateException("摄像头或麦克风编码器初始化失败")
                    }
                    pushStream = stream
                    if (previewRequested) publisherSurface?.let(stream::startPreview)
                }
        }.getOrElse { error ->
            Log.e(LOG_TAG, "Create RTMP stream failed", error)
            emit(LiveMediaEventType.ERROR, error.message ?: "创建 Android 推流器失败")
            null
        }
    }

    private fun emit(type: LiveMediaEventType, message: String, retryCount: Int? = null) {
        // Pigeon 的 FlutterApi 是 suspend 调用，因此在主线程协程中发送；异常不应
        // 反向打崩播放器生命周期。
        eventScope.launch {
            runCatching {
                eventApi.onEvent(LiveMediaEvent(type, message, retryCount?.toLong()))
            }
        }
    }

    fun dispose() {
        cancelReconnect()
        runCatching { pushStream?.stopStream() }
        runCatching { pushStream?.stopPreview() }
        runCatching { pushStream?.release() }
        pushStream = null
        player.release()
        eventScope.cancel()
    }

    fun attachPublisherSurface(surfaceView: SurfaceView) {
        publisherSurface = surfaceView
        if (previewRequested && pushStream?.isOnPreview == false) {
            pushStream?.startPreview(surfaceView)
        }
    }

    fun detachPublisherSurface(surfaceView: SurfaceView) {
        if (publisherSurface === surfaceView) publisherSurface = null
    }

    /** RootEncoder 的连接回调被转换成跨平台 Pigeon 事件。 */
    private inner class PushConnectChecker : ConnectChecker {
        override fun onConnectionStarted(url: String) {
            Log.i(LOG_TAG, "RTMP connection started: $url")
        }

        override fun onConnectionSuccess() {
            Log.i(LOG_TAG, "RTMP connection success")
            emit(LiveMediaEventType.PUSH_STARTED, "RTMP 推流已连接")
        }

        override fun onNewBitrate(bitrate: Long) {
            Log.d(LOG_TAG, "RTMP bitrate=$bitrate")
        }

        override fun onDisconnect() {
            Log.i(LOG_TAG, "RTMP disconnected")
            emit(LiveMediaEventType.ERROR, "RTMP 推流连接已断开")
        }

        override fun onAuthError() {
            emit(LiveMediaEventType.ERROR, "RTMP 推流鉴权失败")
        }

        override fun onAuthSuccess() {
            Log.i(LOG_TAG, "RTMP authentication success")
        }

        override fun onConnectionFailed(reason: String) {
            Log.w(LOG_TAG, "RTMP connection failed: $reason")
            emit(LiveMediaEventType.ERROR, "RTMP 推流连接失败：$reason")
        }
    }
}

private class AndroidLiveMediaPlayerViewFactory(
    private val player: ExoPlayer,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    // 每个 AndroidView 都从这里创建，但所有视图共享插件持有的 ExoPlayer。
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return AndroidLiveMediaPlayerView(context, player)
    }
}

private class AndroidLiveMediaPlayerView(
    context: Context,
    player: ExoPlayer,
) : PlatformView {
    // PlayerView 只是渲染容器，播放控制权仍归 AndroidLiveMediaEngine。
    private val playerView = PlayerView(context).apply {
        this.player = player
        useController = false
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        setShutterBackgroundColor(Color.BLACK)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        // 只解除视图与播放器的引用，不在这里 release 全局播放器；插件销毁时统一释放。
        playerView.player = null
    }
}

private class AndroidLiveMediaPublisherViewFactory(
    private val engine: AndroidLiveMediaEngine,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return AndroidLiveMediaPublisherView(context, engine)
    }
}

/**
 * 主播 PlatformView。
 *
 * SurfaceView 只是把摄像头预览画面交给 Flutter；RTMP 连接、编码和重连都由
 * AndroidLiveMediaEngine 控制，所以页面销毁时不会把业务状态藏在 View 里。
 */
private class AndroidLiveMediaPublisherView(
    context: Context,
    private val engine: AndroidLiveMediaEngine,
) : PlatformView {
    private val surfaceView = SurfaceView(context)

    init {
        engine.attachPublisherSurface(surfaceView)
    }

    override fun getView(): View = surfaceView

    override fun dispose() {
        engine.detachPublisherSurface(surfaceView)
    }
}
