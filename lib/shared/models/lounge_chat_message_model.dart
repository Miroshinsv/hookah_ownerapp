class LoungeChatMessageModel {
  final String messageId;
  final String? senderId;
  final String? senderRole;
  final String text;
  final DateTime createdAt;

  const LoungeChatMessageModel({
    required this.messageId,
    this.senderId,
    this.senderRole,
    required this.text,
    required this.createdAt,
  });

  factory LoungeChatMessageModel.fromJson(Map<String, dynamic> json) =>
      LoungeChatMessageModel(
        messageId: (json['messageId'] ?? json['id']) as String,
        senderId: json['senderId'] as String?,
        senderRole: json['senderRole'] as String?,
        text: json['text'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
      );
}
