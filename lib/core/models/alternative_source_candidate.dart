import 'video_item.dart';
import 'vod_source.dart';

class AlternativeSourceCandidate {
  const AlternativeSourceCandidate({
    required this.source,
    required this.video,
  });

  final VodSource source;
  final VideoItem video;
}
