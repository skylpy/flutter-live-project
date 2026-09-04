import AVFoundation
import Flutter
import UIKit

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
    emit(type: .initialized, message: "AVPlayer 已初始化")
    return true
  }

  func play(url: String) async throws -> Bool {
    guard let mediaURL = validatedURL(from: url) else {
      emit(type: .error, message: "仅支持 HTTP/HTTPS 播放地址")
      return false
    }
    return await MainActor.run {
      currentURL = mediaURL
      retryCount = 0
      retryWorkItem?.cancel()
      return beginPlayback(url: mediaURL)
    }
  }

  func stop() async throws -> Bool {
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
    let event = LiveMediaEvent(type: type, message: message, retryCount: retryCount)
    Task {
      try? await flutterApi.onEvent(event: event)
    }
  }

  private func validatedURL(from value: String) -> URL? {
    guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else {
      return nil
    }
    return url
  }
}
