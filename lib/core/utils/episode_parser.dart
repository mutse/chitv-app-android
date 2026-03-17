import '../models/episode_item.dart';

class EpisodeParser {
  List<EpisodeItem> parse(String raw) {
    if (raw.trim().isEmpty) return const [];

    final firstSource = raw.split(r'$$$').first.trim();
    final delimiter = firstSource.contains('#') ? '#' : '|';
    final parts = firstSource.split(delimiter);

    final result = <EpisodeItem>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i].trim();
      if (p.isEmpty) continue;

      final seg = p.split('');
      final normalized = seg.last;
      final splitAt = normalized.indexOf(r'$');
      final name = splitAt == -1
          ? '第${i + 1}集'
          : normalized.substring(0, splitAt).trim().isEmpty
              ? '第${i + 1}集'
              : normalized.substring(0, splitAt).trim();
      final rawUrl = splitAt == -1
          ? normalized.trim()
          : normalized.substring(splitAt + 1).trim();

      final url = _normalizeUrl(rawUrl);
      if (!_isPlayable(url)) continue;

      result.add(EpisodeItem(name: name, url: url, index: result.length));
    }

    if (result.isEmpty) {
      final fallback = _normalizeUrl(firstSource);
      if (_isPlayable(fallback)) {
        result.add(EpisodeItem(name: '第1集', url: fallback, index: 0));
      }
    }

    return result;
  }

  String _normalizeUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;

    value = value.replaceAll(r'\/', '/');
    if (value.startsWith('//')) {
      value = 'https:$value';
    }

    final lower = value.toLowerCase();
    if (lower.startsWith('http%3a') || lower.startsWith('https%3a')) {
      try {
        value = Uri.decodeFull(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  bool _isPlayable(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}
