import AVFoundation
import Flutter
import UIKit

/// iOS 原生播放器插件。
///
/// Flutter 通过 Pigeon 调用本类，AVPlayer 负责解析和播放，PlatformView 负责
/// 把视频画面显示到 Flutter 布局中。这样 UI 层不需要了解 Swift 或 AVFoundation。
public final class FlutterLiveMediaPlugin: NSObject, FlutterPlugin, LiveMediaHostApi {
  // Pigeon 生成的 FlutterApi：原生播放器状态通过它回传到 Dart。
  // 页面不会直接读取 AVPlayer，而是只接收 LiveEngineEvent。
  private let flutterApi: LiveMediaFlutterApi

  // 当前真正负责播放的 AVPlayer。重连时会创建新的 AVPlayer，避免继续复用
  // 已经进入 failed 状态的 AVPlayerItem。
  private var player: AVPlayer?

  // PlatformView 由 Flutter 创建和持有，因此插件只弱引用它，避免播放器插件
  // 反过来延长页面视图生命周期，造成直播间退出后仍然占用 UI 资源。
  private weak var playerView: FlutterLiveMediaPlayerView?

  // 当前播放地址是“播放会话”的唯一标识。stop() 会清空它，让已经排队的
  // 重连任务失效；进入另一个直播间时会替换它。
  private var currentURL: URL?

  // 当前播放会话已经重连的次数。每次新的 play() 都会归零，最多尝试 3 次。
  private var retryCount = 0
  private let maxRetryCount = 3

  // DispatchWorkItem 代表一次尚未执行的重连任务。保存它是为了在 stop()、
  // 新的 play() 或播放器恢复时取消旧任务，避免多个重连同时启动。
  private var retryWorkItem: DispatchWorkItem?

  // AVPlayerItem.status：用于判断资源是否加载失败。
  private var statusObservation: NSKeyValueObservation?

  // AVPlayer.timeControlStatus：用于区分 playing、buffering 等播放状态。
  private var timeControlObservation: NSKeyValueObservation?

  // NotificationCenter 观察卡顿、播放失败和自然结束。数组统一保存 token，
  // 清理时逐个移除，避免旧 AVPlayer 继续向页面发送事件。
  private var notificationTokens: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    // messenger 是 FlutterEngine 的平台消息通道。Pigeon 会在这条通道上
    // 注册 HostApi，同时使用同一个通道把事件发回 Dart。
    flutterApi = LiveMediaFlutterApi(binaryMessenger: messenger)
    super.init()
  }

  deinit {
    // 插件对象销毁时做最后一次资源清理，防止 KVO 和延迟重连持有闭包引用。
    clearPlayerObservers()
    retryWorkItem?.cancel()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    // FlutterEngine 启动插件时进入这里。
    //
    // 注册完成后会形成两条通道：
    // 1. Flutter/Dart → Pigeon HostApi → 本类的 initialize/play/stop；
    // 2. 本类 → Pigeon FlutterApi → Dart 的 LiveEngine.events。
    // 同时注册 PlatformView，保证 Dart 的 UiKitView 能找到下面的原生 View。
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
    // 当前阶段不需要预先创建 AVPlayer；真正的 AVPlayer 会在 play() 时创建。
    // 仍然保留 initialize()，是为了与 FlutterLiveCore 的 LiveEngine 生命周期
    // 保持一致，未来可以在这里配置音频会话、硬件解码或预加载策略。
    emit(type: .initialized, message: "AVPlayer 已初始化")
    return true
  }

  func play(url: String) async throws -> Bool {
    // 播放链路：FlutterLiveMediaEngine.play()
    //   → Pigeon LiveMediaHostApi.play()
    //   → 本方法校验 URL
    //   → beginPlayback() 创建 AVPlayerItem/AVPlayer
    //   → AVPlayer 回调 playing/buffering/error
    //   → Pigeon FlutterApi.onEvent()
    //   → Flutter 页面更新播放器状态。
    // 先在 Swift 层过滤协议，避免把 RTMP、WebRTC 等尚未实现的地址交给 AVPlayer。
    guard let mediaURL = validatedURL(from: url) else {
      emit(type: .error, message: "仅支持 HTTP/HTTPS 播放地址")
      return false
    }
    return await MainActor.run {
      // AVPlayer、AVPlayerItem、PlatformView 和观察者都在主线程操作。
      // 这样可以避免一边重连一边销毁 View 时出现竞态条件。
      currentURL = mediaURL
      retryCount = 0
      retryWorkItem?.cancel()
      return beginPlayback(url: mediaURL)
    }
  }

  func stop() async throws -> Bool {
    // stop() 的顺序很重要：
    // 1. 先清空 currentURL，让已排队的重连闭包无法重新播放旧房间；
    // 2. 取消延迟任务和观察者，防止旧播放器继续回调；
    // 3. 暂停并释放 AVPlayer；
    // 4. 让 PlatformView 解除 player 引用，但保留 View 本身供页面复用。
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
    // 每次首次播放或重连都重新创建 AVPlayerItem 和 AVPlayer。
    // 原因是 AVPlayerItem 失败后继续复用，可能停留在 failed 状态，无法可靠地
    // 重新加载 HLS 清单；重建对象可以让请求从 Manifest 重新开始。
    clearPlayerObservers()
    let item = AVPlayerItem(url: url)
    let nextPlayer = AVPlayer(playerItem: item)
    nextPlayer.automaticallyWaitsToMinimizeStalling = false

    // 先暂停并替换旧播放器，再把新播放器交给 PlatformView。PlatformView 的
    // 宿主 View 不变，所以重连不会让 Flutter 页面重新布局。
    player?.pause()
    player = nextPlayer
    playerView?.setPlayer(nextPlayer)

    // 必须在安装观察者之后开始播放，否则极快出现的初始状态可能被漏掉。
    observe(player: nextPlayer, item: item)
    nextPlayer.play()
    return true
  }

  private func observe(player: AVPlayer, item: AVPlayerItem) {
    // 这里把 Apple 平台的多种回调统一成 LiveMediaEvent：
    // - KVO item.status：资源准备失败；
    // - KVO timeControlStatus：正在播放或等待缓冲；
    // - NotificationCenter：卡顿、播放失败、自然结束。
    // Flutter 页面只处理统一事件，不需要了解 KVO 或 NotificationCenter。
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
        // 卡顿不一定会让 item.status 进入 failed，所以单独触发重连。
        self?.scheduleRetry(message: "网络波动，准备重连")
      }
    )
    notificationTokens.append(
      center.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] notification in
        // failedToPlayToEndTime 通常包含更具体的系统错误原因，把它传给 Flutter
        // 便于页面显示和后续日志定位。
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
        // 当前测试地址是 VOD HLS，真实直播通常不会自然结束；保留该事件是为了
        // 兼容录播、回放和未来的直播结束状态。
        self?.emit(type: .completed, message: "播放结束")
      }
    )
  }

  private func scheduleRetry(message: String) {
    // 重连状态机：
    //   第 1 次等待 1 秒
    //   第 2 次等待 2 秒
    //   第 3 次等待 4 秒
    // 三次都失败后只发送 error，不再无限重试，避免弱网环境下不断创建播放器。
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
      // 用户离开房间或切换房间后 currentURL 会被清空或替换，因此旧任务不会
      // 复活旧播放器。这个判断是“停止后不重连”的最后一道保护。
      guard let self, let url = self.currentURL else { return }
      self.player = nil
      _ = self.beginPlayback(url: url)
    }
    retryWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func clearPlayerObservers() {
    // 释放 NSKeyValueObservation 会停止 KVO；移除 Notification token 会停止
    // NotificationCenter 回调。每次重建播放器前都必须调用，避免旧 item 和新
    // item 同时产生事件。
    statusObservation = nil
    timeControlObservation = nil
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
    notificationTokens.removeAll()
  }

  private func attach(view: FlutterLiveMediaPlayerView) {
    // PlatformView 创建时可能早于或晚于 play()。无论顺序如何，都把当前 player
    // 绑定给新 View，保证页面旋转/重建后仍能显示当前播放内容。
    playerView = view
    view.setPlayer(player)
  }

  private func emit(
    type: LiveMediaEventType,
    message: String,
    retryCount: Int64? = nil
  ) {
    // Pigeon FlutterApi 是异步回调。try? 表示 Flutter 页面销毁或 Engine 正在
    // detach 时，回调失败不会反向打断播放器清理流程。
    let event = LiveMediaEvent(type: type, message: message, retryCount: retryCount)
    // Pigeon 的 FlutterApi 必须从 Flutter 平台线程发送。AVPlayer 的 KVO 和
    // Notification 回调虽然通常在主线程，但 Swift Task 默认不保证继承这个
    // 调度器；显式切回 MainActor，避免运行时出现“非平台线程发送消息”警告，
    // 也避免 RECONNECTING/PLAYING 事件在高负载时丢失。
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        try? await self.flutterApi.onEvent(event: event)
      }
    }
  }

  private func validatedURL(from value: String) -> URL? {
    // URL 校验集中在入口：当前只允许 HTTP/HTTPS/HLS。未来接入 RTMP、HTTP-FLV
    // 或 WebRTC 时，应在协议抽象层增加对应播放器，而不是直接放宽这里的校验。
    guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else {
      return nil
    }
    return url
  }
}
