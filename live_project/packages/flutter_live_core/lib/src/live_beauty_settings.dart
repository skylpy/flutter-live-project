/// 主播端实时美颜参数。
///
/// 所有数值都在 `0.0` 到 `1.0` 之间：Flutter 负责提供交互，原生媒体引擎
/// 负责把这些参数应用到“采集 → 编码 → 推流”链路。因此主播预览和观众端看到
/// 的是同一份已处理视频帧。
final class LiveBeautySettings {
  const LiveBeautySettings({
    this.smoothing = 0.38,
    this.whitening = 0.10,
    this.rosiness = 0.08,
    this.faceSlimming = 0.25,
    this.filterStrength = 0.72,
  });

  /// 磨皮强度。
  final double smoothing;

  /// 美白强度。
  final double whitening;

  /// 红润强度。
  final double rosiness;

  /// 瘦脸强度。原生层仅在人脸区域被识别后进行局部 GPU 形变。
  final double faceSlimming;

  /// 整体滤镜强度；为 0 时保留原始画面。
  final double filterStrength;

  /// 不启用任何美颜的设置，可用于“原图”或重置。
  static const disabled = LiveBeautySettings(
    smoothing: 0,
    whitening: 0,
    rosiness: 0,
    faceSlimming: 0,
    filterStrength: 0,
  );

  LiveBeautySettings copyWith({
    double? smoothing,
    double? whitening,
    double? rosiness,
    double? faceSlimming,
    double? filterStrength,
  }) {
    return LiveBeautySettings(
      smoothing: smoothing ?? this.smoothing,
      whitening: whitening ?? this.whitening,
      rosiness: rosiness ?? this.rosiness,
      faceSlimming: faceSlimming ?? this.faceSlimming,
      filterStrength: filterStrength ?? this.filterStrength,
    );
  }

  /// 边界收敛放在跨平台核心层，防止 Platform Channel 收到非法参数。
  LiveBeautySettings get normalized => LiveBeautySettings(
    smoothing: smoothing.clamp(0, 1).toDouble(),
    whitening: whitening.clamp(0, 1).toDouble(),
    rosiness: rosiness.clamp(0, 1).toDouble(),
    faceSlimming: faceSlimming.clamp(0, 1).toDouble(),
    filterStrength: filterStrength.clamp(0, 1).toDouble(),
  );

  @override
  bool operator ==(Object other) {
    return other is LiveBeautySettings &&
        other.smoothing == smoothing &&
        other.whitening == whitening &&
        other.rosiness == rosiness &&
        other.faceSlimming == faceSlimming &&
        other.filterStrength == filterStrength;
  }

  @override
  int get hashCode =>
      Object.hash(smoothing, whitening, rosiness, faceSlimming, filterStrength);
}
