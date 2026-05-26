class RatingModel {
  final String ratingId;
  final String userId; // телефон / ID рейтингующего
  final String targetType; // "lounge" или "staff"
  final String targetId;
  final int score; // 1–5
  final DateTime createdAt;

  const RatingModel({
    required this.ratingId,
    required this.userId,
    required this.targetType,
    required this.targetId,
    required this.score,
    required this.createdAt,
  });

  factory RatingModel.fromJson(Map<String, dynamic> json) => RatingModel(
        ratingId: json['ratingId'] as String,
        userId: json['userId'] as String,
        targetType: json['targetType'] as String,
        targetId: json['targetId'] as String,
        score: json['score'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}
