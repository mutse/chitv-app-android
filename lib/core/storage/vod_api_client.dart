import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/video_item.dart';

class VodDetailResult {
  const VodDetailResult({required this.video, required this.episodesRaw});

  final VideoItem video;
  final String episodesRaw;
}

class VodApiClient {
  VodApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json,text/plain,*/*',
  };

  Future<List<VideoItem>> search({
    required String baseUrl,
    required String sourceId,
    required String query,
    int page = 1,
  }) async {
    final candidates = <Map<String, String>>[
      {
        'ac': 'videolist',
        if (query.trim().isNotEmpty) 'wd': query.trim(),
        if (page > 1) 'page': '$page',
      },
      {
        'ac': 'videolist',
        if (query.trim().isNotEmpty) 'wd': query.trim(),
        if (page > 1) 'pg': '$page',
      },
      {
        'ac': 'list',
        if (query.trim().isNotEmpty) 'wd': query.trim(),
        if (page > 1) 'page': '$page',
      },
      {
        'ac': 'videolist',
        if (query.trim().isNotEmpty) 'keyword': query.trim(),
        if (page > 1) 'page': '$page',
      },
    ];

    Object? lastError;
    for (final params in candidates) {
      try {
        final uri = _buildUri(baseUrl, params);
        final resp = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12));
        if (resp.statusCode != 200) {
          lastError = 'HTTP ${resp.statusCode}';
          continue;
        }

        final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawList = _extractList(jsonMap);
        if (rawList.isEmpty) {
          continue;
        }
        return rawList
            .map((e) => _toVideoItem(e, sourceId: sourceId))
            .where((e) => e.id.isNotEmpty && e.title.isNotEmpty)
            .toList();
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    if (lastError != null) throw Exception('search failed: $lastError');
    return const [];
  }

  Future<VodDetailResult> detail({
    required String baseUrl,
    required String sourceId,
    required String id,
  }) async {
    final detailCandidates = <Map<String, String>>[
      {'ac': 'detail', 'ids': id},
      {'ac': 'videolist', 'ids': id},
      {'ac': 'list', 'ids': id},
    ];

    for (final params in detailCandidates) {
      final uri = _buildUri(baseUrl, params);
      final resp = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) continue;

      final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = _extractList(jsonMap);
      if (list.isEmpty) continue;

      final item = list.first;
      final video = _toVideoItem(item, sourceId: sourceId);
      final episodesRaw = (item['vod_play_url'] as String? ?? '').trim();
      return VodDetailResult(video: video, episodesRaw: episodesRaw);
    }

    throw Exception('detail list empty');
  }

  VideoItem _toVideoItem(Map<String, dynamic> map, {required String sourceId}) {
    final id = '${map['vod_id'] ?? map['id'] ?? ''}'.trim();
    final title = '${map['vod_name'] ?? map['name'] ?? '未知标题'}';
    final desc = '${map['vod_content'] ?? map['vod_blurb'] ?? ''}';
    final poster = '${map['vod_pic'] ?? map['pic'] ?? ''}';
    final playUrl = '${map['vod_play_url'] ?? ''}';

    return VideoItem(
      id: id,
      title: title,
      description: desc,
      poster: poster,
      url: _firstPlayable(playUrl),
      sourceId: sourceId,
      vodPlayUrl: playUrl,
    );
  }

  String _firstPlayable(String raw) {
    if (raw.isEmpty) return '';
    final src = raw.split(r'$$$').first;
    final ep = src.split('#').first;
    final pair = ep.split(r'$');
    if (pair.length < 2) return '';
    final url = pair.last.trim();
    return url.startsWith('http') ? url : '';
  }

  Future<int?> probeLatency({required String baseUrl}) async {
    final started = DateTime.now();
    final uri = Uri.parse(baseUrl).replace(queryParameters: const {
      'ac': 'videolist',
      'wd': '测试',
      'page': '1',
    });

    try {
      final resp = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      return DateTime.now().difference(started).inMilliseconds;
    } catch (_) {
      return null;
    }
  }

  Uri _buildUri(String baseUrl, Map<String, String> params) {
    final base = Uri.parse(baseUrl.trim());
    final merged = <String, String>{...base.queryParameters, ...params};
    return base.replace(queryParameters: merged);
  }

  List<Map<String, dynamic>> _extractList(Map<String, dynamic> map) {
    final listLike = map['list'] ??
        (map['data'] is Map ? (map['data'] as Map)['list'] : null) ??
        (map['data'] is List ? map['data'] : null) ??
        map['result'];

    if (listLike is! List) return const [];
    return listLike
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
