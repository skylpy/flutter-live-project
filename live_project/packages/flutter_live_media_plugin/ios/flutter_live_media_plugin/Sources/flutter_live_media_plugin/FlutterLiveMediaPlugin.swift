import AVFoundation
import Flutter
import UIKit

/// iOS 原生播放器插件。
///
/// Flutter 通过 Pigeon 调用本类，AVPlayer 负责解析和播放，PlatformView 负责
/// 把视频画面显示到 Flutter 布局中。这样 UI 层不需要了解 Swift 或 AVFoundation。
public final class FlutterLiveMediaPlugin: NSObject, FlutterPlugin, LiveMediaHostApi {
  private let flutterApi: LiveMediaFlutterApi
  private var player: AVPlayer?
  private weak var playerView: FlutterLiveMediaPlayerView?
  private var currentURL: URL?
  private var retryCount = 0
  private let maxRetryCount = 3
  private var retryWorkItem: DispatchWorkItem?
  private var statusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var notificationTokens: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    flutterApi = LiveMediaFlutterApi(binaryMessenger: messenger)
    super.init()
  }

  deinit {
    clearPlayerObservers()
    retryWorkItem?.cancel()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    // 插件注册时同时绑定 Pigeon 消息接口和原生视频视图工厂。
    let instance = FlutterLiveMediaPlugin(messenger: registrar.messenger())
    LiveMediaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.register(
      FlutterLiveMediaPlayerViewFactory { [weak instance] view in
        instance?.attach(view: view)
      },
      withId: "flutter_live_media_player_view"
    )
  }

  func initialize(configuration: LiveEngineConfiguration) async throws -> Bool {
    // 当前播放器对象按播放请求创建；保留初始化接口是为了兼容 LiveEngine 生命周期。
    emit(type: .initialized, message: "AVPlayer 已初始化")
    return true
  }

  func play(url: String) async throws -> Bool {
    // 先在 Swift 层过滤协议，避免把 RTMP 等尚未实现的地址交给 AVPlayer。
    guard let mediaURL = validatedURL(from: url) else {
      emit(type: .error, message: "仅支持 HTTP/HTTPS 播放地址")
      return false
    }
    return await MainActor.run {
      // AVPlayer 和其观察者都在主线程操作，避免 KVO/视图更新出现竞态。
      currentURL = mediaURL
      retryCount = 0
      retryWorkItem?.cancel()
      return beginPlayback(url: mediaURL)
    }
  }

  func stop() async throws -> Bool {
    // 清空 currentURL 会让已经排队的重试失效，随后解除观察者并断开视图引用。
    await MainActor.run {
      currentURL = nil
      retryWorkItem?.cancel()
      retryWorkItem = nil
      clearPlayerObservers()
      player?.pause()
      player = nil
      playerView?.setPlayer(nil)
    }
    emit(type: .stopped, message: "播放器已停止")
    return true
  }

  private func beginPlayback(url: URL) -> Bool {
    // 每次重试重新创建 AVPlayerItem，避免复用已失败的 item。
    clearPlayerObservers()
    let item = AVPlayerItem(url: url)
    let nextPlayer = AVPlayer(playerItem: item)
    nextPlayer.automaticallyWaitsToMinimizeStalling = false
    player?.pause()
    player = nextPlayer
    playerView?.setPlayer(nextPlayer)
    observe(player: nextPlayer, item: item)
    nextPlayer.play()
    return true
  }

  private func observe(player: AVPlayer, item: AVPlayerItem) {
    // KVO 负责缓冲/播放状态，NotificationCenter 负责卡顿、失败和自然结束事件。
    statusObservation = item.observe(\.status, options: [.initial, .new]) {
      [weak self] item, _ in
      if item.status == .failed {
        self?.scheduleRetry(message: item.error?.localizedDescription ?? "播放失败")
      }
    }
    timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) {
      [weak self] player, _ in
      switch player.timeControlStatus {
      case .playing:
        self?.emit(type: .playing, message: "正在播放")
      case .waitingToPlayAtSpecifiedRate:
        self?.emit(type: .buffering, message: "正在缓冲")
      case .paused:
        break
      @unknown default:
        break
      }
    }

    let center = NotificationCenter.default
    notificationTokens.append(
      center.addObserver(
        forName: .AVPlayerItemPlaybackStalled,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.scheduleRetry(message: "网络波动，准备重连")
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] notification in
        let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
          as? Error)?.localizedDescription ?? "播放失败"
        self?.scheduleRetry(message: message)
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        self?.emit(type: .completed, message: "播放结束")
      }
    )
  }

  private func scheduleRetry(message: String) {
    // 指数退避可给网络恢复时间，也避免故障时频繁创建播放器。
    guard currentURL != nil else { return }
    guard retryCount < maxRetryCount else {
      emit(type: .error, message: "重连失败，请稍后重试")
      return
    }

    retryCount += 1
    emit(type: .reconnecting, message: message, retryCount: Int64(retryCount))
    retryWorkItem?.cancel()
    let delay = pow(2.0, Double(retryCount - 1))
    let workItem = DispatchWorkItem { [weak self] in
      // 用户离开房间或换房后 currentURL 会被清空，因此旧任务不会复活旧播放器。
      guard let self, let url = self.currentURL else { return }
      self.player = nil
      _ = self.beginPlayback(url: url)
    }
    retryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func clearPlayerObservers() {
    statusObservation = nil
    timeControlObservation = nil
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
    notificationTokens.removeAll()
  }

  private func attach(view: FlutterLiveMediaPlayerView) {
    playerView = view
    view.setPlayer(player)
  }

  private func emit(
    type: LiveMediaEventType,
    message: String,
    retryCount: Int64? = nil
  ) {
    // Pigeon FlutterApi 是异步回调；try? 表示 Flutter 页面销毁时不让回调异常
    // 反向影响原生播放器生命周期。
    let event = LiveMediaEvent(type: type, message: message, retryCount: retryCount)
    Task {
      try? await flutterApi.onEvent(event: event)
    }
  }

  private func validatedURL(from value: String) -> URL? {
    // URL 校验集中在入口，后续新增协议时只修改这里和原生播放器实现。
    guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else {
      return nil
    }
    return url
  }
}
