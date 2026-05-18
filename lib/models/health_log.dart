class HealthLog {
  final String id;
  final String text;
  final String type;
  final DateTime time;
  final Map<String, dynamic> metadata;

  HealthLog({
    required this.id,
    required this.text,
    required this.type,
    required this.time,
    required this.metadata,
  });

  factory HealthLog.fromMap(Map<String, dynamic> map) {
    return HealthLog(
      id: map['node_id'],
      text: map['raw_text'] ?? map['name'] ?? '',
      type: map['event_type'] ?? map['type'] ?? 'other',
      time: DateTime.parse(map['event_time'] ?? map['created_at']),
      metadata: map,
    );
  }
}
