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

  // 让 AVPlayerLayer 直接成为 UIView 的 backing layer。相比把播放器层作为
  // 普通 sublayer 动态添加，这种方式能让 UIKit/Flutter PlatformView 在布局、
  // 尺寸变化和模拟器渲染路径下始终使用同一个视频输出层。
  override class var layerClass: AnyClass {
    AVPlayerLayer.self
  }

  private var playerLayer: AVPlayerLayer {
    // 因为 layerClass 返回 AVPlayerLayer，所以这里拿到的就是 View 的 backing
    // layer，而不是额外创建的 CALayer。这样 Flutter PlatformView 的尺寸变化
    // 会自然传递给视频层。
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    // View 创建时还没有播放器，先显示黑色背景和 AVPlayer 占位文字。
    // play() 成功绑定 AVPlayer 后，setPlayer() 会隐藏这段文字。
    super.init(frame: frame)
    backgroundColor = .black
    clipsToBounds = true
    playerLayer.videoGravity = .resizeAspect

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
    // 直接替换 backing layer 的 AVPlayer，不叠加多个视频层，也不改变 Flutter
    // PlatformView 的宿主视图；播放器重连时只会替换这里的 player 引用。
    playerLayer.player = player
    label.isHidden = player != nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
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
/// HaishinKit 的 HKView 内部使用 AVCaptureVideoPreviewLayer，并且可以直接
/// attach 同一个 RTMPStream 的 mixer session。这样画面和推流使用同一套采集数据，
/// 不会因为单独创建预览 session 而重复占用摄像头或造成画面不同步。
final class FlutterLiveMediaPublisherView: NSObject, FlutterPlatformView {
  // HKView 不是 open class，插件不能通过继承扩展它；使用容器组合 HKView，
  // 同时保留 FlutterPlatformView 所需的稳定 UIView 生命周期。
  private let containerView: UIView
  private let previewView: HKView

  init(frame: CGRect) {
    containerView = UIView(frame: frame)
    previewView = HKView(frame: frame)
    super.init()

    containerView.backgroundColor = .black
    previewView.videoGravity = .resizeAspectFill
    previewView.videoOrientation = .portrait
    previewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    previewView.frame = containerView.bounds
    containerView.addSubview(previewView)
  }

  func view() -> UIView {
    containerView
  }

  func setStream(_ stream: RTMPStream?) {
    // detach 时 HKView 会停止 AVCaptureSession；结束直播后可安全释放摄像头。
    previewView.attachStream(stream)
    previewView.videoOrientation = .portrait
  }
}
