import media from '@ohos.multimedia.media';
import { BusinessError } from '@ohos.base';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { SurfaceTextureEntry, TextureRegistry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import { LiveMediaEvent, LiveMediaEventType } from './LiveMediaPigeonCodec';

const TAG: string = 'FlutterLiveMediaNativePlayer';

// 重连参数与 Android/iOS 实现保持一致，方便跨平台行为可预期。
// 第一次等待 1 秒，之后按指数退避等待 2 秒、4 秒，最多尝试 3 次。
const MAX_RECONNECT_ATTEMPTS: number = 3;
const FIRST_RECONNECT_DELAY_MILLIS: number = 1000;

type NativeEventCallback = (event: LiveMediaEvent) => void;

/**
 * OpenHarmony 原生播放对象。
 *
 * 链路是：Dart LiveEngine → Pigeon HostApi → 本类 → AVPlayer；画面则是
 * AVPlayer → SurfaceTextureEntry → Flutter Texture。这样播放器生命周期只在
 * 原生层管理，Flutter 侧只持有抽象接口和事件流。
 */
export class LiveMediaNativePlayer {
  private readonly textureRegistry: TextureRegistry;
  private readonly onEvent: NativeEventCallback;
  private textureEntry: SurfaceTextureEntry | null = null;
  private avPlayer: media.AVPlayer | null = null;
  private pendingUrl: string = '';
  private playWhenPrepared: boolean = false;
  private released: boolean = false;
  private reconnectAttempt: number = 0;
  private reconnectTimer: number | null = null;
  private playerState: media.AVPlayerState | null = null;

  constructor(textureRegistry: TextureRegistry, onEvent: NativeEventCallback) {
    this.textureRegistry = textureRegistry;
    this.onEvent = onEvent;
  }

  /** 创建一次纹理；textureId 会通过独立的只读 MethodChannel 返回给 Dart。 */
  ensureTexture(): number {
    if (this.textureEntry == null) {
      const textureId = this.textureRegistry.getTextureId();
      this.textureEntry = this.textureRegistry.registerTexture(textureId);
      Log.i(TAG, 'registered Flutter texture, id=' + textureId);
    }
    return this.textureEntry.getTextureId();
  }

  async initialize(): Promise<boolean> {
    if (this.released) return false;
    this.ensureTexture();
    if (!(await this.createPlayer())) return false;
    this.emit(LiveMediaEventType.INITIALIZED, 'OpenHarmony AVPlayer 已初始化');
    return true;
  }

  async play(url: string): Promise<boolean> {
    const normalizedUrl = url.trim();
    if (this.released || normalizedUrl.length === 0) return false;

    // play 是用户主动发起的新播放请求，因此要清掉上一次失败留下的
    // 重连计数和定时器，避免新请求被旧请求的状态影响。
    this.cancelReconnect(true);
    this.pendingUrl = normalizedUrl;
    this.playWhenPrepared = true;

    if (this.avPlayer == null && !(await this.initialize())) return false;
    if (this.avPlayer == null) return false;

    // stop() 会主动释放 AVPlayer；另外，某些系统版本在播放器进入
    // stopped/released 后不能再次给同一个对象设置 url。遇到这两种状态
    // 时重建播放器，保证“停止后再次播放”走一条干净的初始化链路。
    if (
      this.playerState === 'stopped' ||
      this.playerState === 'released' ||
      this.playerState === 'error'
    ) {
      return this.rebuildPlayer('再次播放');
    }

    // AVPlayer 的 URL 属性必须在 idle 状态设置；后续状态回调会负责 prepare。
    this.avPlayer.url = this.pendingUrl;
    Log.i(TAG, 'HLS play requested: ' + this.pendingUrl);
    return true;
  }

  stop(): boolean {
    // 主动停止与异常停止必须区分开：主动停止后不应该自动重连。
    this.playWhenPrepared = false;
    this.pendingUrl = '';
    this.cancelReconnect(true);

    const player = this.avPlayer;
    this.avPlayer = null;
    this.playerState = null;
    if (player != null) {
      // 直接 release 可以同时覆盖 idle、prepared、playing 等状态，且让
      // 下一次 play 必然创建全新的 AVPlayer，避免 5400102 无效状态错误。
      player.release();
    }
    this.emit(LiveMediaEventType.STOPPED, 'OpenHarmony 播放已停止');
    return true;
  }

  release(): void {
    if (this.released) return;
    this.released = true;
    this.playWhenPrepared = false;
    this.pendingUrl = '';
    this.cancelReconnect(true);

    // 先把引用置空，再释放旧对象。旧对象稍后回调 released/error 时，
    // isCurrentPlayer() 会将其识别为过期回调，不会污染新播放器状态。
    const player = this.avPlayer;
    this.avPlayer = null;
    this.playerState = null;
    if (player != null) {
      player.release();
    }
    if (this.textureEntry != null) {
      this.textureRegistry.unregisterTexture(this.textureEntry.getTextureId());
      this.textureEntry = null;
    }
  }

  /**
   * 创建 AVPlayer，但不创建 Texture。
   *
   * Texture 是 Flutter 侧的渲染资源，生命周期应比一次播放会话更长；
   * 重连时只替换 AVPlayer，并把同一个 surfaceId 重新交给新播放器，
   * 这样 Dart 侧不需要重新挂载 PlatformView/Texture。
   */
  private async createPlayer(): Promise<boolean> {
    if (this.released) return false;
    if (this.avPlayer != null) return true;

    try {
      const player = await media.createAVPlayer();
      if (this.released) {
        player.release();
        return false;
      }
      this.avPlayer = player;
      this.playerState = null;
      this.bindPlayerEvents(player);
      return true;
    } catch (error) {
      Log.e(TAG, 'createAVPlayer failed: ' + JSON.stringify(error));
      return false;
    }
  }

  /**
   * 释放旧播放器并创建新播放器。
   *
   * 只允许当前播放请求触发重建；旧 AVPlayer 的异步回调会因为对象引用
   * 不再等于 this.avPlayer 而被忽略，从根上避免旧回调把新播放器打断。
   */
  private async rebuildPlayer(reason: string): Promise<boolean> {
    if (this.released || !this.playWhenPrepared || this.pendingUrl.length === 0) {
      return false;
    }

    const url = this.pendingUrl;
    const oldPlayer = this.avPlayer;
    this.avPlayer = null;
    this.playerState = null;
    if (oldPlayer != null) {
      Log.w(TAG, 'rebuild AVPlayer, reason=' + reason);
      oldPlayer.release();
    }

    if (!(await this.createPlayer())) return false;
    if (!this.setPlayerUrl(url)) return false;
    Log.i(TAG, 'rebuilt AVPlayer and requested HLS URL: ' + url);
    return true;
  }

  /** 在当前播放器仍有效时设置 URL，单独封装以便异步重建后再次做空值保护。 */
  private setPlayerUrl(url: string): boolean {
    if (this.avPlayer == null) return false;
    this.avPlayer.url = url;
    return true;
  }

  private bindPlayerEvents(player: media.AVPlayer): void {
    player.on('stateChange', async (state: media.AVPlayerState) => {
      if (!this.isCurrentPlayer(player)) return;
      Log.i(TAG, 'AVPlayer state=' + state);
      this.playerState = state;
      switch (state) {
        case 'initialized':
          if (this.textureEntry != null) {
            player.surfaceId = this.textureEntry.getSurfaceId().toString();
          }
          try {
            await player.prepare();
          } catch (error) {
            this.handlePlayerFailure(player, error, 'prepare');
          }
          break;
        case 'prepared':
          this.emit(LiveMediaEventType.INITIALIZED, 'OpenHarmony HLS 已准备');
          if (this.playWhenPrepared && this.isCurrentPlayer(player)) {
            try {
              await player.play();
            } catch (error) {
              this.handlePlayerFailure(player, error, 'play');
            }
          }
          break;
        case 'playing':
          // 只有真正收到 playing，才认为本次重连成功并清零计数。
          this.cancelReconnect(true);
          this.emit(LiveMediaEventType.PLAYING, 'OpenHarmony HLS 播放中');
          break;
        case 'completed':
          this.emit(LiveMediaEventType.COMPLETED, 'OpenHarmony 播放完成');
          break;
        case 'stopped':
          if (this.playWhenPrepared) {
            this.scheduleReconnect('OpenHarmony AVPlayer 意外停止');
          }
          break;
        case 'released':
          if (this.playWhenPrepared) {
            this.scheduleReconnect('OpenHarmony AVPlayer 意外释放');
          }
          break;
        default:
          break;
      }
    });

    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      if (!this.isCurrentPlayer(player)) return;
      Log.i(TAG, 'bufferingUpdate type=' + infoType + ', value=' + value);
      this.emit(LiveMediaEventType.BUFFERING, 'OpenHarmony HLS 缓冲中');
    });

    player.on('error', (error: BusinessError) => {
      if (!this.isCurrentPlayer(player)) return;
      Log.e(TAG, 'AVPlayer error=' + JSON.stringify(error));
      const message = 'OpenHarmony AVPlayer 错误: ' + error.code;
      this.emit(LiveMediaEventType.ERROR, message);
      this.scheduleReconnect(message);
    });
  }

  /** 判断回调是否仍属于当前播放器，过滤 release 后迟到的旧回调。 */
  private isCurrentPlayer(player: media.AVPlayer): boolean {
    return !this.released && this.avPlayer === player;
  }

  /** 将 prepare/play 的 Promise 异常统一转换成可重连的播放器故障。 */
  private handlePlayerFailure(player: media.AVPlayer, error: ESObject, action: string): void {
    if (!this.isCurrentPlayer(player)) return;
    Log.e(TAG, 'AVPlayer ' + action + ' failed: ' + JSON.stringify(error));
    const code = (error as BusinessError).code;
    const message = 'OpenHarmony AVPlayer ' + action + ' 失败: ' + code;
    this.emit(LiveMediaEventType.ERROR, message);
    this.scheduleReconnect(message);
  }

  /**
   * 安排一次带指数退避的重连。
   * reconnectTimer 同时承担“去重锁”的作用，短时间内收到多个 error
   * 回调时只会保留一个定时任务。
   */
  private scheduleReconnect(reason: string): void {
    if (this.released || !this.playWhenPrepared || this.pendingUrl.length === 0) return;
    if (this.reconnectTimer != null) return;
    if (this.reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) {
      this.emit(
        LiveMediaEventType.ERROR,
        'OpenHarmony 播放重连失败，已达到最大重试次数'
      );
      Log.e(TAG, 'reconnect exhausted, reason=' + reason);
      return;
    }

    this.reconnectAttempt += 1;
    const attempt = this.reconnectAttempt;
    const delay = FIRST_RECONNECT_DELAY_MILLIS * Math.pow(2, attempt - 1);
    this.emit(
      LiveMediaEventType.RECONNECTING,
      'OpenHarmony 正在重连（第 ' + attempt + ' 次）',
      attempt
    );
    Log.w(TAG, 'schedule reconnect attempt=' + attempt + ', delay=' + delay);

    this.reconnectTimer = setTimeout(async () => {
      this.reconnectTimer = null;
      if (this.released || !this.playWhenPrepared || this.pendingUrl.length === 0) return;
      const rebuilt = await this.rebuildPlayer('重连第 ' + attempt + ' 次');
      if (!rebuilt) this.scheduleReconnect('播放器重建失败');
    }, delay);
  }

  /** 清除待执行重连；resetAttempt 只在主动新播放或播放成功时使用。 */
  private cancelReconnect(resetAttempt: boolean): void {
    if (this.reconnectTimer != null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (resetAttempt) this.reconnectAttempt = 0;
  }

  private emit(type: LiveMediaEventType, message: string, retryCount: number | null = null): void {
    const event = new LiveMediaEvent();
    event.type = type;
    event.message = message;
    event.retryCount = retryCount;
    this.onEvent(event);
  }
}
