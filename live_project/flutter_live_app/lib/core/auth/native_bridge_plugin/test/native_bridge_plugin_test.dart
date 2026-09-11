import 'package:flutter_test/flutter_test.dart';
import 'package:native_bridge_plugin/native_bridge_plugin.dart';
import 'package:native_bridge_plugin/native_bridge_plugin_platform_interface.dart';
import 'package:native_bridge_plugin/native_bridge_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNativeBridgePluginPlatform
    with MockPlatformInterfaceMixin
    implements NativeBridgePluginPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final NativeBridgePluginPlatform initialPlatform = NativeBridgePluginPlatform.instance;

  test('$MethodChannelNativeBridgePlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNativeBridgePlugin>());
  });

  test('getPlatformVersion', () async {
    NativeBridgePlugin nativeBridgePlugin = NativeBridgePlugin();
    MockNativeBridgePluginPlatform fakePlatform = MockNativeBridgePluginPlatform();
    NativeBridgePluginPlatform.instance = fakePlatform;

    expect(await nativeBridgePlugin.getPlatformVersion(), '42');
  });
}
