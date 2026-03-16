import '../models/episode_item.dart';

class EpisodeParser {
  List<EpisodeItem> parse(String raw) {
    if (raw.trim().isEmpty) return const [];

    final firstSource = raw.split(r'$$$').first;
    final parts = firstSource.split('#');

    final result = <EpisodeItem>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i].trim();
      if (p.isEmpty) continue;

      final seg = p.split('');
      final normalized = seg.last;
      final pair = normalized.split(r'$');

      if (pair.length < 2) continue;
      final name = pair.first.trim().isEmpty ? '第${i + 1}集' : pair.first.trim();
      final url = pair.last.trim();
      if (!url.startsWith('http')) continue;

      result.add(EpisodeItem(name: name, url: url, index: result.length));
    }
    return result;
  }
}
