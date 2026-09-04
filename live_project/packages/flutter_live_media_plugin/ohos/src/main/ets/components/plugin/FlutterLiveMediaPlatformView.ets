import common from '@ohos.app.ability.common';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';

/**
 * 当前阶段的 PlatformView 占位组件。
 *
 * 真实 HLS 画面使用 Flutter 外接纹理，因为这是 OpenHarmony 官方 video_player
 * 的成熟链路；PlatformView 仍然保留并注册，后续如果需要原生控件同层渲染，
 * Flutter 侧只需切换到 OhosView，不必重新设计插件注册协议。
 */
@Component
struct FlutterLiveMediaPlaceholderComponent {
  @Prop params: Params;

  build() {
    Stack() {
      Text('OpenHarmony PlatformView\n播放器渲染占位')
        .fontColor(Color.White)
        .fontSize(16)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .alignContent(Alignment.Center)
  }
}

@Builder
function buildFlutterLiveMediaPlaceholder(params: Params) {
  FlutterLiveMediaPlaceholderComponent({ params: params });
}

export class FlutterLiveMediaPlatformView extends PlatformView {
  constructor(
    context: common.Context,
    viewId: number,
    args: ESObject,
    message: BinaryMessenger
  ) {
    super();
  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(buildFlutterLiveMediaPlaceholder);
  }

  dispose(): void {
    // 当前占位控件没有额外资源；真实同层播放器接入后在这里释放 AVPlayer。
  }
}

export class FlutterLiveMediaPlatformViewFactory extends PlatformViewFactory {
  private readonly messenger: BinaryMessenger;

  constructor(messenger: BinaryMessenger, codec: MessageCodec<Object>) {
    super(codec);
    this.messenger = messenger;
  }

  create(
    context: common.Context,
    viewId: number,
    args: ESObject
  ): PlatformView {
    return new FlutterLiveMediaPlatformView(context, viewId, args, this.messenger);
  }
}
