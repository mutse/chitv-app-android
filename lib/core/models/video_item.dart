class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.description,
    required this.poster,
    required this.url,
    required this.sourceId,
    this.vodPlayUrl,
  });

  final String id;
  final String title;
  final String description;
  final String poster;
  final String url;
  final String sourceId;
  final String? vodPlayUrl;

  VideoItem copyWith({
    String? id,
    String? title,
    String? description,
    String? poster,
    String? url,
    String? sourceId,
    String? vodPlayUrl,
  }) {
    return VideoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      poster: poster ?? this.poster,
      url: url ?? this.url,
      sourceId: sourceId ?? this.sourceId,
      vodPlayUrl: vodPlayUrl ?? this.vodPlayUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'poster': poster,
    'url': url,
    'sourceId': sourceId,
    'vodPlayUrl': vodPlayUrl,
  };

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      url: json['url'] as String? ?? '',
      sourceId: json['sourceId'] as String,
      vodPlayUrl: json['vodPlayUrl'] as String?,
    );
  }
}
