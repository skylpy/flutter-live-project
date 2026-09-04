package com.skylpy.flutter_live_media_plugin

import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
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
private const val MAX_RECONNECT_ATTEMPTS = 3

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
    // ExoPlayer 负责真正的媒体解析和播放；Flutter 只通过接口调用它。
    val player: ExoPlayer = ExoPlayer.Builder(context.applicationContext).build()

    private val eventApi = LiveMediaFlutterApi(messenger)
    private val eventScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentUrl: String? = null
    private var reconnectAttempt = 0
    private var reconnectRunnable: Runnable? = null

    init {
        // Player.Listener 是 ExoPlayer 的状态出口。这里只转换状态并发送统一事件，
        // 不把 ExoPlayer 类型泄露给 Flutter 层。
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> emit(LiveMediaEventType.BUFFERING, "播放器缓冲中")
                    Player.STATE_READY -> emit(LiveMediaEventType.PLAYING, "播放器播放中")
                    Player.STATE_ENDED -> emit(LiveMediaEventType.COMPLETED, "播放已完成")
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                // 先通知当前错误，再安排指数退避重连；这样 UI 可以立即显示网络异常。
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
        // setMediaItem 只设置媒体项，prepare 才开始解析；playWhenReady 表示解析
        // 成功后自动播放。真正 READY 的时刻由 listener 回调给 Flutter。
        player.setMediaItem(MediaItem.fromUri(normalizedUrl))
        player.prepare()
        player.playWhenReady = true
        return true
    }

    override suspend fun stop(): Boolean {
        // 清理当前 URL 很重要：它会阻止已经排队的重连任务重新启动旧直播间。
        cancelReconnect()
        reconnectAttempt = 0
        currentUrl = null
        player.stop()
        player.clearMediaItems()
        emit(LiveMediaEventType.STOPPED, "Android 播放器已停止")
        return true
    }

    private fun scheduleReconnect() {
        val url = currentUrl ?: return
        if (reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) {
            emit(LiveMediaEventType.ERROR, "播放器重连次数已耗尽")
            return
        }

        reconnectAttempt += 1
        val attempt = reconnectAttempt
        // 1s、2s、4s 的指数退避，避免网络故障时高频重试压垮服务端。
        val delayMillis = 1000L shl (attempt - 1)
        emit(
            LiveMediaEventType.RECONNECTING,
            "播放器将在 ${delayMillis / 1000} 秒后重连",
            attempt,
        )

        val runnable = Runnable {
            // 用户如果已经切换房间或停止播放，旧任务即使执行也不能重新播放。
            if (currentUrl != url) return@Runnable
            player.setMediaItem(MediaItem.fromUri(url))
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
        player.release()
        eventScope.cancel()
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
