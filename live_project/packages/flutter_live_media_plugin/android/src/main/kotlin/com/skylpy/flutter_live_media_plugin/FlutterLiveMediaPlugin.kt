package com.skylpy.flutter_live_media_plugin

import android.content.Context
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.TextureView
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.sources.OrientationForced
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.encoder.input.video.facedetector.FaceDetectorCallback
import com.pedro.encoder.input.sources.video.Camera2Source
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max

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
    private var publisherTexture: TextureView? = null
    private var previewRequested = false
    private var beautySettings = LiveBeautyConfiguration(
        smoothing = 0.38,
        whitening = 0.10,
        rosiness = 0.08,
        faceSlimming = 0.25,
        filterStrength = 0.72,
    )
    private var beautyFilter: LiveBeautyFilterRender? = null
    @Volatile private var faceRegion: FaceRegion? = null
    private var faceTrackingEnabled = false

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
        startPreviewIfSurfaceReady(stream)
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
        previewRequested = true
        // PlatformView 的 SurfaceView 可能还没有完成 surfaceCreated；先记录请求，
        // 待 SurfaceHolder.Callback 回调后再启动预览，推流连接本身不应因 Surface
        // 创建时序而失败。
        startPreviewIfSurfaceReady(stream)
        emit(LiveMediaEventType.PUSH_CONNECTING, "正在连接 RTMP 推流服务器")
        return runCatching {
            // 部分真机在 startPreview 返回后还需要一个很短的时间完成
            // MediaCodec 的 CSD/首帧初始化；过早发送 RTMP 视频包会让 SRS
            // 把 AVC 配置包误判为 Annex-B NALU 并立即断开。这个有界预热不
            // 影响正常开播时延，却避免把“握手成功但媒体无效”误报为开播成功。
            delay(500)
            stream.startStream(normalizedUrl)
            true
        }.getOrElse { error ->
            Log.e(LOG_TAG, "RTMP push start failed", error)
            emit(LiveMediaEventType.ERROR, error.message ?: "RTMP 推流启动失败")
            false
        }
    }

    override suspend fun switchCamera(): Boolean {
        val stream = pushStream
        if (stream == null) {
            emit(LiveMediaEventType.ERROR, "摄像头预览尚未启动")
            return false
        }
        return runCatching {
            // RootEncoder 会在同一个采集会话内切换前后摄像头，保留当前
            // 编码器、RTMP 连接和 Surface，因此切换时不会结束直播间。
            val videoSource = stream.videoSource
            if (videoSource !is Camera2Source) {
                emit(LiveMediaEventType.ERROR, "当前推流器不支持摄像头切换")
                return false
            }
            videoSource.switchCamera()
            // 不同厂商切换镜头时对 Camera2 人脸检测的保留行为并不一致。显式重新
            // 注册，保证瘦脸不会停留在旧镜头最后一张脸的位置。
            faceTrackingEnabled = false
            faceRegion = null
            beautyFilter?.clearFaceRegion()
            enableFaceTracking(stream)
            emit(LiveMediaEventType.PREVIEW_STARTED, "摄像头已切换")
            true
        }.getOrElse { error ->
            Log.e(LOG_TAG, "Switch camera failed", error)
            emit(LiveMediaEventType.ERROR, error.message ?: "切换摄像头失败")
            false
        }
    }

    override suspend fun setBeautySettings(configuration: LiveBeautyConfiguration): Boolean {
        beautySettings = configuration.normalized()
        pushStream?.let(::applyBeautyFilter)
        // Filter 更新发生在 RootEncoder 的 GL 管线；同一纹理后续会同时进入
        // TextureView 预览和 MediaCodec，因此无需单独维护一套 Flutter 预览特效。
        return true
    }

    override suspend fun stopPush(): Boolean {
        // 先停网络推流，再停预览；否则摄像头仍会被编码器占用，下一次开播可能
        // 拿不到 Camera2 资源。这里不影响观众端 ExoPlayer。
        pushStream?.let { stream ->
            (stream.videoSource as? Camera2Source)?.disableFaceDetection()
            runCatching { stream.stopStream() }
            runCatching { stream.stopPreview() }
        }
        previewRequested = false
        faceTrackingEnabled = false
        faceRegion = null
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
                    // 720p/30fps/2.5Mbps 用于保证手机端竖屏画面细节；局域网和常规
                    // Wi-Fi 下比 1.2Mbps 更适合直播，同时仍然保留对中端设备的余量。
                    // 弱网自适应后续再接入；prepare* 返回 false 时不能启动推流。
                    // SRS 的 HLS 切片会在关键帧处切开。这里使用六参数重载，显式
                    // 设置 2 秒关键帧间隔，让不同 Android 编码器都遵守直播切片
                    // 所需的 GOP 粒度，避免观众端等待很长时间才出现第一帧。
                    val videoReady = stream.prepareVideo(720, 1280, 2_500_000, 30, 0, 2)
                    // 编码尺寸是竖屏还不够：RootEncoder 的 GL 渲染也必须使用
                    // PORTRAIT，否则部分真机会输出 720x1280 的容器尺寸，但把
                    // 摄像头内容按横屏方向绘制到预览和 RTMP 流里。
                    val glInterface = stream.getGlInterface()
                    glInterface.forceOrientation(OrientationForced.PORTRAIT)
                    // 设备已经锁定竖屏，保留相机原始方向，避免部分真机后置相机
                    // 再被旋转 90°/270°；竖屏画布和编码宽高仍由 PORTRAIT 模式
                    // 固定为 720x1280。
                    glInterface.setCameraOrientation(0)
                    applyBeautyFilter(stream)
                    // RootEncoder 的参数顺序是 sampleRate、stereo、bitrate；不能
                    // 按常见的 bitrate、stereo、sampleRate 顺序传递，否则会生成
                    // 64000Hz AAC，部分 Android/Media3 解码器会拒绝这种音频流。
                    val audioReady = stream.prepareAudio(44_100, true, 64_000)
                    if (!videoReady || !audioReady) {
                        stream.release()
                        throw IllegalStateException("摄像头或麦克风编码器初始化失败")
                    }
                    pushStream = stream
                    if (previewRequested) startPreviewIfSurfaceReady(stream)
                }
        }.getOrElse { error ->
            Log.e(LOG_TAG, "Create RTMP stream failed", error)
            emit(LiveMediaEventType.ERROR, error.message ?: "创建 Android 推流器失败")
            null
        }
    }

    private fun startPreviewIfSurfaceReady(stream: RtmpStream) {
        val textureView = publisherTexture ?: return
        if (textureView.isAvailable && !stream.isOnPreview) {
            stream.startPreview(textureView)
        }
        // 预览早已启动、但硬件检测第一次暂不可用时，下一次 UI attach 仍可重试。
        enableFaceTracking(stream)
    }

    private fun applyBeautyFilter(stream: RtmpStream) {
        val settings = beautySettings
        val nextFilter = LiveBeautyFilterRender().apply {
            update(
                smoothing = settings.smoothing.toFloat(),
                whitening = settings.whitening.toFloat(),
                rosiness = settings.rosiness.toFloat(),
                faceSlimming = settings.faceSlimming.toFloat(),
                filterStrength = settings.filterStrength.toFloat(),
            )
            faceRegion?.let { region ->
                updateFaceRegion(
                    centerX = region.centerX,
                    centerY = region.centerY,
                    radiusX = region.radiusX,
                    radiusY = region.radiusY,
                )
            }
        }
        // setFilter 会在 RootEncoder 的 GL 渲染链替换前一个滤镜；切换参数不会
        // 重启 Camera2、MediaCodec 或 RTMP 连接，观众只会看到平滑的帧级变化。
        stream.getGlInterface().setFilter(nextFilter)
        beautyFilter = nextFilter
    }

    private fun enableFaceTracking(stream: RtmpStream) {
        if (faceTrackingEnabled) return
        val source = stream.videoSource as? Camera2Source ?: return
        // RootEncoder 使用 Camera2 的硬件人脸检测，避免为瘦脸额外复制每一帧
        // Bitmap 或引入云端/第三方模型。部分低端镜头不支持时会返回 false；那种
        // 情况保持其他美颜能力，但不会对背景做错误的“全屏瘦脸”形变。
        faceTrackingEnabled = source.enableFaceDetection(
            object : FaceDetectorCallback {
                override fun onGetFaces(
                    faces: Array<com.pedro.encoder.input.video.facedetector.Face>,
                    scaleSensor: android.graphics.Rect?,
                    sensorOrientation: Int,
                ) {
                    val primaryFace = faces.maxByOrNull { it.score }
                    if (primaryFace == null || scaleSensor == null || scaleSensor.width() <= 0 || scaleSensor.height() <= 0) {
                        faceRegion = null
                        beautyFilter?.clearFaceRegion()
                        return
                    }
                    val sourceX = (primaryFace.rect.centerX() - scaleSensor.left).toFloat() / scaleSensor.width()
                    val sourceY = (primaryFace.rect.centerY() - scaleSensor.top).toFloat() / scaleSensor.height()
                    val sourceRadiusX = primaryFace.rect.width().toFloat() / scaleSensor.width() * 0.62f
                    val sourceRadiusY = primaryFace.rect.height().toFloat() / scaleSensor.height() * 0.58f
                    val oriented = orientFaceRegion(
                        sourceX = sourceX,
                        sourceY = sourceY,
                        radiusX = sourceRadiusX,
                        radiusY = sourceRadiusY,
                        rotation = sensorOrientation,
                        mirrored = source.getCameraFacing() == CameraHelper.Facing.FRONT,
                    )
                    faceRegion = oriented
                    beautyFilter?.updateFaceRegion(
                        centerX = oriented.centerX,
                        centerY = oriented.centerY,
                        radiusX = oriented.radiusX,
                        radiusY = oriented.radiusY,
                    )
                }
            },
        )
    }

    private fun orientFaceRegion(
        sourceX: Float,
        sourceY: Float,
        radiusX: Float,
        radiusY: Float,
        rotation: Int,
        mirrored: Boolean,
    ): FaceRegion {
        val (rotatedX, rotatedY, rotatedRadiusX, rotatedRadiusY) = when ((rotation % 360 + 360) % 360) {
            90 -> FaceRegion(sourceY, 1f - sourceX, radiusY, radiusX)
            180 -> FaceRegion(1f - sourceX, 1f - sourceY, radiusX, radiusY)
            270 -> FaceRegion(1f - sourceY, sourceX, radiusY, radiusX)
            else -> FaceRegion(sourceX, sourceY, radiusX, radiusY)
        }
        return FaceRegion(
            centerX = if (mirrored) 1f - rotatedX else rotatedX,
            centerY = rotatedY,
            radiusX = rotatedRadiusX.coerceIn(0.08f, 0.46f),
            radiusY = rotatedRadiusY.coerceIn(0.08f, 0.46f),
        )
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
        beautyFilter = null
        faceRegion = null
        faceTrackingEnabled = false
        player.release()
        eventScope.cancel()
    }

    private fun LiveBeautyConfiguration.normalized(): LiveBeautyConfiguration =
        LiveBeautyConfiguration(
            smoothing = smoothing.safeUnitInterval(),
            whitening = whitening.safeUnitInterval(),
            rosiness = rosiness.safeUnitInterval(),
            faceSlimming = faceSlimming.safeUnitInterval(),
            filterStrength = filterStrength.safeUnitInterval(),
        )

    private fun Double.safeUnitInterval(): Double =
        if (!isFinite()) 0.0 else coerceIn(0.0, 1.0)

    private data class FaceRegion(
        val centerX: Float,
        val centerY: Float,
        val radiusX: Float,
        val radiusY: Float,
    )

    fun attachPublisherTexture(textureView: TextureView) {
        publisherTexture = textureView
        if (
            previewRequested &&
            pushStream != null
        ) {
            pushStream?.let(::startPreviewIfSurfaceReady)
        }
    }

    fun detachPublisherTexture(textureView: TextureView) {
        if (publisherTexture === textureView) publisherTexture = null
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
    // Flutter 的混合合成模式下，PlayerView 默认使用 SurfaceView；在部分
    // Android 模拟器/设备上会出现解码正常但截图和 Flutter 叠加层花屏的问题。
    // TextureView 走 Flutter 兼容的纹理合成路径，避免 SurfaceView 穿透/撕裂。
    private val textureView = TextureView(context)
    private val exoPlayer = player
    private val container = FrameLayout(context).apply {
        setBackgroundColor(android.graphics.Color.BLACK)
        addView(
            textureView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER,
            ),
        )
    }
    private val playerListener = object : Player.Listener {
        override fun onVideoSizeChanged(videoSize: VideoSize) {
            applyCenterCrop(videoSize)
        }
    }

    init {
        exoPlayer.addListener(playerListener)
        exoPlayer.setVideoTextureView(textureView)
        // Media3 自己管理 TextureView 的 SurfaceTextureListener；这里不覆盖它，
        // 只在绑定完成后的布局帧补一次裁切，后续尺寸变化由 onVideoSizeChanged
        // 统一处理，避免插件自身重复接管 SurfaceTexture 生命周期。
        textureView.post { applyCenterCrop(exoPlayer.videoSize) }
    }

    private fun applyCenterCrop(videoSize: VideoSize) {
        val viewWidth = textureView.width.toFloat()
        val viewHeight = textureView.height.toFloat()
        if (viewWidth <= 0f || viewHeight <= 0f || videoSize.width <= 0 || videoSize.height <= 0) {
            return
        }

        val videoWidth = videoSize.width * videoSize.pixelWidthHeightRatio
        val videoHeight = videoSize.height.toFloat()
        val scale = maxOf(viewWidth / videoWidth, viewHeight / videoHeight)
        val matrix = Matrix().apply {
            setScale(
                videoWidth * scale / viewWidth,
                videoHeight * scale / viewHeight,
                viewWidth / 2f,
                viewHeight / 2f,
            )
        }
        textureView.setTransform(matrix)
    }

    override fun getView(): View = container

    override fun dispose() {
        // 只解除纹理和监听，不在这里 release 全局播放器；插件销毁时统一释放。
        exoPlayer.removeListener(playerListener)
        exoPlayer.clearVideoTextureView(textureView)
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
 * TextureView 把摄像头预览画面交给 Flutter。这里不能使用 SurfaceView：全屏
 * SurfaceView 会盖住 Flutter 的主播控制层；TextureView 仍由 RootEncoder 作为
 * 预览目标，同时允许 Flutter 的切换/结束按钮叠加在视频上。
 */
private class AndroidLiveMediaPublisherView(
    context: Context,
    private val engine: AndroidLiveMediaEngine,
) : PlatformView {
    private val textureView = TextureView(context)
    private val textureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(
            surface: android.graphics.SurfaceTexture,
            width: Int,
            height: Int,
        ) {
            // TextureView 的 SurfaceTexture 创建晚于 PlatformView；只有此时
            // 才把预览目标交给 RootEncoder，避免页面重建时使用失效纹理。
            engine.attachPublisherTexture(textureView)
            applyPortraitCenterCrop(width, height)
        }

        override fun onSurfaceTextureSizeChanged(
            surface: android.graphics.SurfaceTexture,
            width: Int,
            height: Int,
        ) {
            engine.attachPublisherTexture(textureView)
            applyPortraitCenterCrop(width, height)
        }

        override fun onSurfaceTextureDestroyed(surface: android.graphics.SurfaceTexture): Boolean {
            engine.detachPublisherTexture(textureView)
            return true
        }

        override fun onSurfaceTextureUpdated(surface: android.graphics.SurfaceTexture) = Unit
    }

    init {
        textureView.setBackgroundColor(android.graphics.Color.BLACK)
        textureView.surfaceTextureListener = textureListener
        engine.attachPublisherTexture(textureView)
    }

    override fun getView(): View = textureView

    /**
     * RootEncoder 输出的是 720x1280 竖屏画面，而真机窗口通常是更高的
     * 9:19.5 比例。TextureView 默认按原始纹理尺寸绘制，会在上下留下黑边；
     * 用 center-crop 把纹理放大到覆盖整个视图，再从左右裁掉多余部分。
     */
    private fun applyPortraitCenterCrop(viewWidth: Int, viewHeight: Int) {
        if (viewWidth <= 0 || viewHeight <= 0) return

        val sourceWidth = 720f
        val sourceHeight = 1280f
        val scale = max(viewWidth / sourceWidth, viewHeight / sourceHeight)
        val scaledWidth = sourceWidth * scale
        val scaledHeight = sourceHeight * scale

        val transform = Matrix().apply {
            setScale(scale, scale)
            postTranslate(
                (viewWidth - scaledWidth) / 2f,
                (viewHeight - scaledHeight) / 2f,
            )
        }
        textureView.setTransform(transform)
    }

    override fun dispose() {
        textureView.surfaceTextureListener = null
        engine.detachPublisherTexture(textureView)
    }
}
