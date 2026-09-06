/// 关注/点赞接口返回的当前状态和总数。
class LiveInteraction {
  const LiveInteraction({required this.active, required this.count});

  final bool active;
  final int count;

  factory LiveInteraction.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
    return LiveInteraction(
      active: json['active'] == true,
      count: json['count'] is int
          ? json['count']! as int
          : int.tryParse('${json['count']}') ?? 0,
    );
  }
}
