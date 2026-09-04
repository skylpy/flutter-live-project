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

/** Android implementation backed by Media3 ExoPlayer. */
class FlutterLiveMediaPlugin : FlutterPlugin {
    private var mediaEngine: AndroidLiveMediaEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val engine = AndroidLiveMediaEngine(binding.applicationContext, binding.binaryMessenger)
        mediaEngine = engine
        LiveMediaHostApi.setUp(binding.binaryMessenger, engine)
        binding.platformViewRegistry.registerViewFactory(
            PLAYER_VIEW_TYPE,
            AndroidLiveMediaPlayerViewFactory(engine.player),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LiveMediaHostApi.setUp(binding.binaryMessenger, null)
        mediaEngine?.dispose()
        mediaEngine = null
    }
}

private class AndroidLiveMediaEngine(
    context: Context,
    messenger: BinaryMessenger,
) : LiveMediaHostApi {
    val player: ExoPlayer = ExoPlayer.Builder(context.applicationContext).build()

    private val eventApi = LiveMediaFlutterApi(messenger)
    private val eventScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var currentUrl: String? = null
    private var reconnectAttempt = 0
    private var reconnectRunnable: Runnable? = null

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> emit(LiveMediaEventType.BUFFERING, "播放器缓冲中")
                    Player.STATE_READY -> emit(LiveMediaEventType.PLAYING, "播放器播放中")
                    Player.STATE_ENDED -> emit(LiveMediaEventType.COMPLETED, "播放已完成")
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                emit(LiveMediaEventType.ERROR, error.message ?: error.errorCodeName)
                scheduleReconnect()
            }
        })
    }

    override suspend fun initialize(configuration: LiveEngineConfiguration): Boolean {
        emit(LiveMediaEventType.INITIALIZED, "Android 媒体引擎已初始化")
        return true
    }

    override suspend fun play(url: String): Boolean {
        val normalizedUrl = url.trim()
        val scheme = Uri.parse(normalizedUrl).scheme?.lowercase()
        if (normalizedUrl.isEmpty() || scheme !in setOf("http", "https")) {
            emit(LiveMediaEventType.ERROR, "当前仅支持 HTTP/HTTPS 播放地址")
            return false
        }

        cancelReconnect()
        reconnectAttempt = 0
        currentUrl = normalizedUrl
        player.setMediaItem(MediaItem.fromUri(normalizedUrl))
        player.prepare()
        player.playWhenReady = true
        return true
    }

    override suspend fun stop(): Boolean {
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
        val delayMillis = 1000L shl (attempt - 1)
        emit(
            LiveMediaEventType.RECONNECTING,
            "播放器将在 ${delayMillis / 1000} 秒后重连",
            attempt,
        )

        val runnable = Runnable {
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
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return AndroidLiveMediaPlayerView(context, player)
    }
}

private class AndroidLiveMediaPlayerView(
    context: Context,
    player: ExoPlayer,
) : PlatformView {
    private val playerView = PlayerView(context).apply {
        this.player = player
        useController = false
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        setShutterBackgroundColor(Color.BLACK)
    }

    override fun getView(): View = playerView

    override fun dispose() {
        playerView.player = null
    }
}
