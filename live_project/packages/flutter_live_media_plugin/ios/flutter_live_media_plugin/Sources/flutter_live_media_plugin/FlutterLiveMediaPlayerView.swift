import AVFoundation
import Flutter
import HaishinKit
import UIKit

/// 创建并把原生播放器视图交给插件实例管理。
final class FlutterLiveMediaPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onViewCreated: (FlutterLiveMediaPlayerView) -> Void

  init(onViewCreated: @escaping (FlutterLiveMediaPlayerView) -> Void) {
    self.onViewCreated = onViewCreated
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    // Flutter 第一次构建 UiKitView 时会调用这里。工厂只负责创建 View，
    // 播放控制仍由 FlutterLiveMediaPlugin 持有的 AVPlayer 完成。
    let view = FlutterLiveMediaPlayerView(frame: frame)
    onViewCreated(view)
    return view
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// iOS PlatformView。
///
/// 这个 View 只负责渲染 AVPlayerLayer，不负责播放控制和重连；控制逻辑位于插件类。
final class FlutterLiveMediaPlayerView: UIView, FlutterPlatformView {
  private let label = UILabel(frame: .zero)

  // 不把 AVPlayerLayer 作为 UIView 的 backing layer。Flutter 的 UiKitView 在
  // 模拟器和真机上都可能重建/替换宿主 layer，独立持有视频子层更稳定，也能
  // 在 layoutSubviews 中明确同步尺寸，避免 AVPlayer 已经 playing 但画面仍为黑屏。
  private let playerLayer = AVPlayerLayer()
  private var currentPlayer: AVPlayer?

  override init(frame: CGRect) {
    // View 创建时还没有播放器，先显示黑色背景和 AVPlayer 占位文字。
    // play() 成功绑定 AVPlayer 后，setPlayer() 会隐藏这段文字。
    super.init(frame: frame)
    backgroundColor = .black
    clipsToBounds = true
    playerLayer.frame = bounds
    playerLayer.backgroundColor = UIColor.black.cgColor
    // 直播间是沉浸式全屏，竖屏画面按比例裁切填满容器，避免黑边。
    playerLayer.videoGravity = .resizeAspectFill
    layer.addSublayer(playerLayer)

    label.text = "AVPlayer"
    label.textColor = UIColor.white.withAlphaComponent(0.65)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func view() -> UIView {
    // FlutterPlatformView 要求返回实际嵌入 Flutter 页面树的 UIView。
    return self
  }

  func setPlayer(_ player: AVPlayer?) {
    // 只替换同一个视频子层的 player，不叠加多个视频层，也不改变 Flutter
    // PlatformView 的宿主视图；播放器重连时只会替换这里的 player 引用。
    currentPlayer = player
    playerLayer.player = player
    label.isHidden = player != nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let hadZeroBounds = playerLayer.bounds.size == .zero
    playerLayer.frame = bounds
    // Flutter 创建 UiKitView 时可能先给出 0×0，下一帧才完成布局。AVPlayerLayer
    // 若在零尺寸时首次绑定播放器，部分 iOS 模拟器/真机不会自动恢复视频输出；
    // 第一次获得有效尺寸后重新挂载同一个 AVPlayer，避免重新请求或重建播放会话。
    if hadZeroBounds, bounds.width > 0, bounds.height > 0, let currentPlayer {
      playerLayer.player = nil
      playerLayer.player = currentPlayer
    }
  }
}

/// 创建 iOS 主播摄像头预览 PlatformView。
final class FlutterLiveMediaPublisherViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onViewCreated: (FlutterLiveMediaPublisherView) -> Void

  init(onViewCreated: @escaping (FlutterLiveMediaPublisherView) -> Void) {
    self.onViewCreated = onViewCreated
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let view = FlutterLiveMediaPublisherView(frame: frame)
    onViewCreated(view)
    return view
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// iOS 主播摄像头预览 View。
///
/// 使用 Metal 渲染 RTMPStream 的编码前处理帧。
///
/// 隐形 MTHKView 仍负责把 HaishinKit 视频 I/O 固定在 Metal 上；可见视图则接收
/// `LiveBeautyVideoEffect` 的最终 CIImage。这样主播看到的是将被编码推给观众的
/// 同一帧，且切换前后摄像头不会重新绑定 AVCaptureVideoPreviewLayer。
final class FlutterLiveMediaPublisherView: NSObject, FlutterPlatformView {
  // MTHKView 作为子视图嵌入稳定的 FlutterPlatformView 容器；这样 Flutter
  // 页面重建时不会重建 RTMPStream 或重新占用摄像头。
  private let containerView: UIView
  private let metalSynchronizerView: MTHKView
  private let processedPreviewView: LiveBeautyPreviewMetalView
  private weak var currentStream: RTMPStream?
  private weak var currentBeautyEffect: LiveBeautyVideoEffect?

  init(frame: CGRect) {
    containerView = UIView(frame: frame)
    metalSynchronizerView = MTHKView(frame: frame)
    processedPreviewView = LiveBeautyPreviewMetalView(frame: frame)
    super.init()

    containerView.backgroundColor = .black
    // MTHKView 会把 stream 的 CIContext 绑定到 Metal；它只作同步器，不能可见，
    // 否则会把 HaishinKit 原始 sampleBuffer 覆盖在美颜预览之上。
    metalSynchronizerView.videoGravity = .resizeAspectFill
    metalSynchronizerView.videoOrientation = .portrait
    metalSynchronizerView.isHidden = true
    metalSynchronizerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    metalSynchronizerView.frame = containerView.bounds
    processedPreviewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    processedPreviewView.frame = containerView.bounds
    containerView.addSubview(metalSynchronizerView)
    containerView.addSubview(processedPreviewView)
  }

  func view() -> UIView {
    containerView
  }

  func setStream(_ stream: RTMPStream?, beautyEffect: LiveBeautyVideoEffect?) {
    // 切换摄像头时 RTMPStream 不会变。相同 stream 不重复 attach，避免替换
    // Metal 的 drawable；结束直播传 nil 才真正 detach 并释放摄像头。
    if let stream, currentStream === stream {
      currentBeautyEffect?.previewSink = nil
      currentBeautyEffect = beautyEffect
      beautyEffect?.previewSink = processedPreviewView
      metalSynchronizerView.videoOrientation = .portrait
      return
    }
    if stream == nil, currentStream == nil {
      return
    }
    currentBeautyEffect?.previewSink = nil
    currentBeautyEffect = beautyEffect
    beautyEffect?.previewSink = processedPreviewView
    currentStream = stream
    // detach 时 MTHKView 会解绑 drawable；插件随后关闭 RTMPStream 的采集会话。
    metalSynchronizerView.attachStream(stream)
    metalSynchronizerView.videoOrientation = .portrait
    if stream == nil {
      processedPreviewView.clear()
    }
  }
}
