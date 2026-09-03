import Flutter
import UIKit

final class FlutterLiveMediaPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return FlutterLiveMediaPlayerView(frame: frame)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

final class FlutterLiveMediaPlayerView: NSObject, FlutterPlatformView {
  private let containerView: UIView

  init(frame: CGRect) {
    containerView = UIView(frame: frame)
    super.init()

    containerView.backgroundColor = .black
    let label = UILabel(frame: .zero)
    label.text = "Native player placeholder"
    label.textColor = UIColor.white.withAlphaComponent(0.65)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
    ])
  }

  func view() -> UIView {
    return containerView
  }
}
