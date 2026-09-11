/// 会话页使用的一条私信；字段兼容后端 camelCase 与测试中的 snake_case。
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.isMine,
    required this.timeLabel,
    this.media = const [],
    this.isVirtual = false,
  });

  final int id;
  final int senderId;
  final int recipientId;
  final String body;
  final bool isMine;
  final String timeLabel;
  final List<DirectMessageMedia> media;
  final bool isVirtual;

  factory DirectMessage.fromJson(Map<String, Object?> json) => DirectMessage(
    id: _asInt(json['id']),
    senderId: _asInt(json['senderId'] ?? json['sender_id']),
    recipientId: _asInt(json['recipientId'] ?? json['recipient_id']),
    body: json['body'] as String? ?? '',
    isMine: json['isMine'] == true || json['is_mine'] == true,
    timeLabel: (json['timeLabel'] ?? json['time_label']) as String? ?? '',
    media: (json['media'] is List ? json['media'] as List : const <Object?>[])
        .whereType<Map>()
        .map(
          (item) =>
              DirectMessageMedia.fromJson(Map<String, Object?>.from(item)),
        )
        .toList(growable: false),
    isVirtual: json['isVirtual'] == true || json['is_virtual'] == true,
  );

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}

/// 一条私信关联的私有 OSS 媒体。链接仅来自会话读取接口，不写入本地缓存。
class DirectMessageMedia {
  const DirectMessageMedia({
    required this.fileId,
    required this.mediaType,
    required this.url,
  });

  final int fileId;
  final String mediaType;
  final String url;

  bool get isVideo => mediaType == 'video';

  factory DirectMessageMedia.fromJson(Map<String, Object?> json) =>
      DirectMessageMedia(
        fileId: DirectMessage._asInt(json['fileId'] ?? json['file_id']),
        mediaType: (json['mediaType'] ?? json['media_type']) as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}
