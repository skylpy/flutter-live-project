import {
  AbilityAware,
  AbilityPluginBinding,
  BinaryMessenger,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { TextureRegistry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import { FlutterLiveMediaPlatformViewFactory } from './FlutterLiveMediaPlatformView';
import { LiveMediaNativePlayer } from './LiveMediaNativePlayer';
import {
  LiveEngineConfiguration,
  LiveMediaEvent,
  LiveMediaEventType,
  LiveMediaPigeonCodec,
} from './LiveMediaPigeonCodec';

const TAG: string = 'FlutterLiveMediaPlugin';
const VIEW_TYPE: string = 'flutter_live_media_player_view';
const HOST_PREFIX: string = 'dev.flutter.pigeon.flutter_live_media_plugin.LiveMediaHostApi.';
const FLUTTER_EVENT_CHANNEL: string =
  'dev.flutter.pigeon.flutter_live_media_plugin.LiveMediaFlutterApi.onEvent';
const OHOS_CONTROL_CHANNEL: string = 'flutter_live_media_plugin/ohos';

/**
 * FlutterLiveMediaPlugin 是鸿蒙侧插件入口。
 *
 * 它做三件事：
 * 1. 注册 Pigeon HostApi，接收 Flutter 的 initialize/play/stop；
 * 2. 把 NativePlayer 事件按 Pigeon FlutterApi 协议回传给 Flutter；
 * 3. 注册 PlatformView 占位和 textureId 查询通道。
 */
export default class FlutterLiveMediaPlugin implements FlutterPlugin, AbilityAware {
  private pluginBinding: FlutterPluginBinding | null = null;
  private abilityBinding: AbilityPluginBinding | null = null;
  private player: LiveMediaNativePlayer | null = null;
  private eventChannel: BasicMessageChannel<Object> | null = null;
  private controlChannel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.pluginBinding = binding;
    Log.i(TAG, 'plugin attached to engine');
    binding.getPlatformViewRegistry()?.registerViewFactory(
      VIEW_TYPE,
      new FlutterLiveMediaPlatformViewFactory(
        binding.getBinaryMessenger(),
        StandardMessageCodec.INSTANCE
      )
    );
    this.registerControlChannel(binding.getBinaryMessenger());
    this.registerHostApi(binding.getBinaryMessenger());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, 'plugin detached from engine');
    this.controlChannel?.setMethodCallHandler(null);
    this.controlChannel = null;
    this.eventChannel?.setMessageHandler(null);
    this.eventChannel = null;
    this.player?.release();
    this.player = null;
    this.pluginBinding = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityBinding = binding;
    if (this.pluginBinding != null) {
      this.player = new LiveMediaNativePlayer(
        this.pluginBinding.getTextureRegistry(),
        (event: LiveMediaEvent) => this.sendEvent(event)
      );
    }
    Log.i(TAG, 'plugin attached to ability');
  }

  onDetachedFromAbility(): void {
    this.player?.release();
    this.player = null;
    this.abilityBinding = null;
    Log.i(TAG, 'plugin detached from ability');
  }

  private registerControlChannel(messenger: BinaryMessenger): void {
    this.controlChannel = new MethodChannel(messenger, OHOS_CONTROL_CHANNEL);
    this.controlChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'getTextureId') {
          result.success(this.player?.ensureTexture() ?? -1);
        } else {
          result.notImplemented();
        }
      },
    });
  }

  private registerHostApi(messenger: BinaryMessenger): void {
    const codec = LiveMediaPigeonCodec.INSTANCE;
    this.registerChannel<Object>(messenger, HOST_PREFIX + 'initialize', codec,
      (message: Object, reply: Reply<Object>): void => {
        try {
          const args: Array<Object> = message as Array<Object>;
          const configuration = args[0] as LiveEngineConfiguration;
          Log.i(TAG, 'initialize hardwareAcceleration=' + configuration.enableHardwareAcceleration);
          const player = this.player;
          if (player == null) {
            reply.reply([false]);
            return;
          }
          player.initialize().then((accepted: boolean) => reply.reply([accepted]));
        } catch (error) {
          reply.reply([false, 'initialize failed', JSON.stringify(error)]);
        }
      });
    this.registerChannel<Object>(messenger, HOST_PREFIX + 'play', codec,
      (message: Object, reply: Reply<Object>): void => {
        try {
          const args: Array<Object> = message as Array<Object>;
          const url = args[0] as string;
          const player = this.player;
          if (player == null) {
            reply.reply([false]);
            return;
          }
          player.play(url).then((accepted: boolean) => reply.reply([accepted]));
        } catch (error) {
          reply.reply([false, 'play failed', JSON.stringify(error)]);
        }
      });
    this.registerChannel<Object>(messenger, HOST_PREFIX + 'stop', codec,
      (message: Object, reply: Reply<Object>): void => {
        reply.reply([this.player?.stop() ?? false]);
      });
  }

  private registerChannel<T>(
    messenger: BinaryMessenger,
    name: string,
    codec: StandardMessageCodec,
    handler: (message: T, reply: Reply<T>) => void
  ): void {
    const channel = new BasicMessageChannel<T>(messenger, name, codec);
    channel.setMessageHandler({
      onMessage: (message: T, reply: Reply<T>): void => handler(message, reply),
    });
  }

  private sendEvent(event: LiveMediaEvent): void {
    if (this.pluginBinding == null) return;
    if (this.eventChannel == null) {
      this.eventChannel = new BasicMessageChannel<Object>(
        this.pluginBinding.getBinaryMessenger(),
        FLUTTER_EVENT_CHANNEL,
        LiveMediaPigeonCodec.INSTANCE
      );
    }
    // Pigeon FlutterApi 的 onEvent 是一个单向 BasicMessageChannel；Flutter
    // 侧收到事件后会返回空响应，原生播放器无需等待该响应才继续播放。
    this.eventChannel.send([event]);
  }
}
