import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/douban_item.dart';

class DoubanApiClient {
  static const String defaultEndpoint =
      'https://movie.douban.com/j/search_subjects';

  DoubanApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<DoubanItem>> fetchHotMovies({
    String proxyBaseUrl = '',
    String endpoint = defaultEndpoint,
    int start = 0,
    int limit = 12,
  }) {
    return _fetchSubjects(
      type: 'movie',
      proxyBaseUrl: proxyBaseUrl,
      endpoint: endpoint,
      start: start,
      limit: limit,
    );
  }

  Future<List<DoubanItem>> fetchHotTvShows({
    String proxyBaseUrl = '',
    String endpoint = defaultEndpoint,
    int start = 0,
    int limit = 12,
  }) {
    return _fetchSubjects(
      type: 'tv',
      proxyBaseUrl: proxyBaseUrl,
      endpoint: endpoint,
      start: start,
      limit: limit,
    );
  }

  Future<List<DoubanItem>> _fetchSubjects({
    required String type,
    required String proxyBaseUrl,
    required String endpoint,
    required int start,
    required int limit,
  }) async {
    final target = _buildTargetUri(endpoint).replace(
      queryParameters: <String, String>{
        'type': type,
        'tag': '热门',
        'sort': 'recommend',
        'page_start': '$start',
        'page_limit': '$limit',
      },
    );

    final uri = _wrapWithProxy(target, proxyBaseUrl);
    final resp = await _client.get(uri, headers: const {
      'Accept': 'application/json,text/plain,*/*',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
    }).timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) return const [];

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final subjects = map['subjects'];
    if (subjects is! List) return const [];

    return subjects
        .whereType<Map>()
        .map((e) => DoubanItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.title.isNotEmpty)
        .toList();
  }

  Uri _buildTargetUri(String endpoint) {
    final parsed = Uri.tryParse(endpoint.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return Uri.parse(defaultEndpoint);
    }
    return parsed;
  }

  Uri _wrapWithProxy(Uri target, String proxyBaseUrl) {
    final proxy = proxyBaseUrl.trim();
    if (proxy.isEmpty) return target;

    final parsed = Uri.tryParse(proxy);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return target;
    }

    final path = _joinPath(parsed.path, '/proxy');
    final query = <String, String>{...parsed.queryParameters, 'url': target.toString()};
    return parsed.replace(path: path, queryParameters: query);
  }

  String _joinPath(String left, String right) {
    final l = left.endsWith('/') ? left.substring(0, left.length - 1) : left;
    final r = right.startsWith('/') ? right : '/$right';
    return '$l$r';
  }
}
