import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';

/**
 * Pigeon 协议中的播放器事件类型。
 *
 * Dart 侧的 Pigeon 编解码器把枚举写成“自定义类型标记 + enum index”。这里
 * 的数字必须与 live_media_api.g.dart 中 LiveMediaEventType.values 的顺序一致，
 * 否则 Flutter 会收到错误的状态名称。
 */
export enum LiveMediaEventType {
  INITIALIZED = 0,
  PLAYING = 1,
  BUFFERING = 2,
  COMPLETED = 3,
  RECONNECTING = 4,
  STOPPED = 5,
  ERROR = 6
}

export class LiveEngineConfiguration {
  enableHardwareAcceleration: boolean = true;

  static fromList(list: Array<ESObject>): LiveEngineConfiguration {
    const result = new LiveEngineConfiguration();
    result.enableHardwareAcceleration = list[0] as boolean ?? true;
    return result;
  }

  toList(): Array<ESObject> {
    return [this.enableHardwareAcceleration];
  }
}

export class LiveMediaEvent {
  type: LiveMediaEventType = LiveMediaEventType.ERROR;
  message: string = '';
  retryCount: number | null = null;

  static fromList(list: Array<ESObject>): LiveMediaEvent {
    const result = new LiveMediaEvent();
    result.type = list[0] as LiveMediaEventType;
    result.message = list[1] as string;
    result.retryCount = list[2] as number | null;
    return result;
  }

  toList(): Array<ESObject> {
    return [this.type, this.message, this.retryCount];
  }
}

/**
 * 与 Dart Pigeon 生成代码对应的 StandardMessageCodec 扩展。
 *
 * OpenHarmony 当前没有直接生成 ArkTS 文件的 Pigeon 流程，所以这里只手写
 * 很薄的一层协议适配；协议源仍然是 pigeons/live_media_api.dart，任何字段
 * 变化都必须同步修改这里和 Dart 生成文件。
 */
export class LiveMediaPigeonCodec extends StandardMessageCodec {
  static INSTANCE: LiveMediaPigeonCodec = new LiveMediaPigeonCodec();

  override readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      // Dart 侧 enum 的自定义类型标记是 129（有符号字节写为 -127）。
      case 129:
        return super.readValue(buffer) as number;
      // Dart 侧 LiveEngineConfiguration 的自定义类型标记是 130。
      case 130:
        return LiveEngineConfiguration.fromList(
          super.readValue(buffer) as Array<ESObject>
        );
      // Dart 侧 LiveMediaEvent 的自定义类型标记是 131。
      case 131:
        return LiveMediaEvent.fromList(super.readValue(buffer) as Array<ESObject>);
      default:
        return super.readValueOfType(type, buffer);
    }
  }

  override writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof LiveEngineConfiguration) {
      // 130 的无符号值在 ByteBuffer 中按有符号 int8 写成 -126。
      stream.writeInt8(-126);
      // 直接写入 List，避免父 codec 遍历 List 时把 enum number 再次递归。
      stream.writeInt8(12);
      stream.writeUint8(1);
      super.writeValue(stream, value.enableHardwareAcceleration);
      return stream;
    }
    if (value instanceof LiveMediaEvent) {
      // 131 的无符号值在 ByteBuffer 中按有符号 int8 写成 -125。
      stream.writeInt8(-125);
      // 写入 Dart List<Object?>[type, message, retryCount]。
      stream.writeInt8(12);
      stream.writeUint8(3);
      // ArkTS enum 在运行时表现为 number，因此只在已知的事件字段位置
      // 写 129 标记；普通 number 交给父 codec，避免递归和误判。
      stream.writeInt8(-127);
      super.writeValue(stream, value.type);
      super.writeValue(stream, value.message);
      super.writeValue(stream, value.retryCount);
      return stream;
    }
    return super.writeValue(stream, value);
  }
}
