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
  private var playerLayer: AVPlayerLayer?
  private let label = UILabel(frame: .zero)

  override init(frame: CGRect) {
    // 先显示黑色占位和文字；真正绑定 AVPlayer 后由 setPlayer 隐藏文字。
    super.init(frame: frame)
    backgroundColor = .black
    clipsToBounds = true

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
    // 重新绑定播放器时先移除旧 layer，防止一个 View 叠加多个视频层。
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    label.isHidden = player != nil

    guard let player else { return }
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspect
    layer.frame = bounds
    self.layer.addSublayer(layer)
    playerLayer = layer
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayer?.frame = bounds
  }
}
