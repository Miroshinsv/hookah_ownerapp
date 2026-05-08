class MessageModel {
  final String id;
  final String? senderId;
  final String? senderRole;
  final String text;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    this.senderId,
    this.senderRole,
    required this.text,
    required this.createdAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) => MessageModel(
        id: json['id'] as String,
        senderId: json['senderId'] as String?,
        senderRole: json['senderRole'] as String?,
        text: json['text'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
