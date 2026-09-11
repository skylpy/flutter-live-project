
import 'native_bridge_plugin_platform_interface.dart';

class NativeBridgePlugin {
  Future<String?> getPlatformVersion() {
    return NativeBridgePluginPlatform.instance.getPlatformVersion();
  }
}
