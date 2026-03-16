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

  Future<List<VideoItem>> search({
    required String baseUrl,
    required String sourceId,
    required String query,
    int page = 1,
  }) async {
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'ac': 'videolist',
      'wd': query,
      if (page > 1) 'page': '$page',
    });

    final resp = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('search failed: ${resp.statusCode}');
    }

    final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (jsonMap['list'] as List<dynamic>? ?? const []);

    return list
        .cast<Map<String, dynamic>>()
        .map((e) => _toVideoItem(e, sourceId: sourceId))
        .toList();
  }

  Future<VodDetailResult> detail({
    required String baseUrl,
    required String sourceId,
    required String id,
  }) async {
    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'ac': 'detail',
      'ids': id,
    });

    final resp = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('detail failed: ${resp.statusCode}');
    }

    final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (jsonMap['list'] as List<dynamic>? ?? const []);
    if (list.isEmpty) {
      throw Exception('detail list empty');
    }

    final item = list.first as Map<String, dynamic>;
    final video = _toVideoItem(item, sourceId: sourceId);
    final episodesRaw = (item['vod_play_url'] as String? ?? '').trim();

    return VodDetailResult(video: video, episodesRaw: episodesRaw);
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
      final resp = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      return DateTime.now().difference(started).inMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
