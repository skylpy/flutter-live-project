import AVFoundation
import Flutter
import UIKit

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

final class FlutterLiveMediaPlayerView: UIView, FlutterPlatformView {
  private var playerLayer: AVPlayerLayer?
  private let label = UILabel(frame: .zero)

  override init(frame: CGRect) {
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
