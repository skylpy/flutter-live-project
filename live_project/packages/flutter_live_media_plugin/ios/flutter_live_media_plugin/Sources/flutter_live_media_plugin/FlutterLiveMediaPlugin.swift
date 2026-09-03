import Flutter
import UIKit

public final class FlutterLiveMediaPlugin: NSObject, FlutterPlugin, LiveMediaHostApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterLiveMediaPlugin()
    LiveMediaHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.register(
      FlutterLiveMediaPlayerViewFactory(),
      withId: "flutter_live_media_player_view"
    )
  }

  func initialize(configuration: LiveEngineConfiguration) async throws -> Bool {
    return true
  }

  func play(url: String) async throws -> Bool {
    return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func stop() async throws -> Bool {
    return true
  }
}
