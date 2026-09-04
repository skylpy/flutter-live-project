import AVFoundation
import Cocoa
import FlutterMacOS

/// 创建 macOS PlatformView，并把 View 交给播放器插件绑定当前 AVPlayer。
final class FlutterLiveMediaPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let onViewCreated: (FlutterLiveMediaPlayerView) -> Void

  init(onViewCreated: @escaping (FlutterLiveMediaPlayerView) -> Void) {
    self.onViewCreated = onViewCreated
    super.init()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let view = FlutterLiveMediaPlayerView(frame: .zero)
    onViewCreated(view)
    return view
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// macOS 的原生视频渲染容器；不直接实现播放和重连。
final class FlutterLiveMediaPlayerView: NSView {
  private var playerLayer: AVPlayerLayer?
  private let label = NSTextField(labelWithString: "AVPlayer")

  override init(frame frameRect: NSRect) {
    // 先显示占位文字；插件绑定 AVPlayer 后再显示视频 layer。
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor

    label.textColor = NSColor.white.withAlphaComponent(0.65)
    label.alignment = .center
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

  func setPlayer(_ player: AVPlayer?) {
    // 绑定新播放器前移除旧 layer，保证同一视图只有一个视频画面。
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    label.isHidden = player != nil

    guard let player else { return }
    let layer = AVPlayerLayer(player: player)
    layer.videoGravity = .resizeAspect
    layer.frame = bounds
    self.layer?.addSublayer(layer)
    playerLayer = layer
  }

  override func layout() {
    super.layout()
    playerLayer?.frame = bounds
  }
}
