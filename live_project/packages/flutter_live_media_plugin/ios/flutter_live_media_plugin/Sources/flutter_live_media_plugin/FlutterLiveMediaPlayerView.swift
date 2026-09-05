import AVFoundation
import Flutter
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
    layer as! AVPlayerLayer
  }

  override init(frame: CGRect) {
    // 先显示黑色占位和文字；真正绑定 AVPlayer 后由 setPlayer 隐藏文字。
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
