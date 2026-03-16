import 'video_item.dart';

class PlaybackHistoryItem {
  const PlaybackHistoryItem({
    required this.video,
    required this.watchedAt,
    this.lastPositionSeconds = 0,
  });

  final VideoItem video;
  final DateTime watchedAt;
  final int lastPositionSeconds;

  Map<String, dynamic> toJson() => {
    'video': video.toJson(),
    'watchedAt': watchedAt.toIso8601String(),
    'lastPositionSeconds': lastPositionSeconds,
  };

  factory PlaybackHistoryItem.fromJson(Map<String, dynamic> json) {
    return PlaybackHistoryItem(
      video: VideoItem.fromJson(json['video'] as Map<String, dynamic>),
      watchedAt: DateTime.parse(json['watchedAt'] as String),
      lastPositionSeconds: json['lastPositionSeconds'] as int? ?? 0,
    );
  }
}
