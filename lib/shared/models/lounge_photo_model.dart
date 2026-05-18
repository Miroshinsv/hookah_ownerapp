class LoungePhotoModel {
  final String id;
  final String url;

  const LoungePhotoModel({required this.id, required this.url});

  factory LoungePhotoModel.fromJson(Map<String, dynamic> json) =>
      LoungePhotoModel(
        id: json['id'] as String,
        url: json['url'] as String,
      );
}
