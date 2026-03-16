import '../models/video_item.dart';

class ContentFilter {
  static const _adultKeywords = <String>[
    '伦理',
    '情色',
    '成人',
    '无码',
    '爆乳',
    'sm',
    '经典三级',
  ];

  List<VideoItem> filterVideos(List<VideoItem> items, {required bool adultFilterEnabled}) {
    if (!adultFilterEnabled) return items;
    return items.where((item) {
      final text = '${item.title} ${item.description}'.toLowerCase();
      return !_adultKeywords.any((k) => text.contains(k));
    }).toList();
  }
}
