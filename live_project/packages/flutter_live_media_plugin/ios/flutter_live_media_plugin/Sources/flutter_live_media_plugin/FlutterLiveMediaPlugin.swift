import AVFoundation
import Flutter
import UIKit

public final class FlutterLiveMediaPlugin: NSObject, FlutterPlugin, LiveMediaHostApi {
  private var player: AVPlayer?
  private weak var playerView: FlutterLiveMediaPlayerView?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterLiveMediaPlugin()
    LiveMediaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.register(
      FlutterLiveMediaPlayerViewFactory { [weak instance] view in
        instance?.attach(view: view)
      },
      withId: "flutter_live_media_player_view"
    )
  }

  func initialize(configuration: LiveEngineConfiguration) async throws -> Bool {
    return true
  }

  func play(url: String) async throws -> Bool {
    guard let mediaURL = validatedURL(from: url) else {
      return false
    }
    let nextPlayer = AVPlayer(url: mediaURL)
    await MainActor.run {
      nextPlayer.automaticallyWaitsToMinimizeStalling = false
      player?.pause()
      player = nextPlayer
      playerView?.setPlayer(nextPlayer)
      nextPlayer.play()
    }
    return true
  }

  func stop() async throws -> Bool {
    await MainActor.run {
      player?.pause()
      player = nil
      playerView?.setPlayer(nil)
    }
    return true
  }

  private func attach(view: FlutterLiveMediaPlayerView) {
    playerView = view
    view.setPlayer(player)
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
