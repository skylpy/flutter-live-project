class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.unread,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String timeLabel;
  final bool unread;

  factory NotificationItem.fromJson(Map<String, Object?> json) =>
      NotificationItem(
        id: '${json['id'] ?? ''}',
        type: _asString(json['type']),
        title: _asString(json['title']),
        body: _asString(json['body']),
        timeLabel: _asString(json['timeLabel'] ?? json['time_label']),
        unread: json['unread'] == true,
      );
}

String _asString(Object? value) => value is String ? value : '';
