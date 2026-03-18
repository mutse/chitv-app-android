import 'dart:async';

import '../core/models/alternative_source_candidate.dart';
import '../core/models/ad_filter.dart';
import '../core/models/episode_item.dart';
import '../core/models/video_item.dart';
import '../core/models/vod_source.dart';
import '../core/storage/vod_api_client.dart';
import '../core/utils/content_filter.dart';
import '../core/utils/episode_parser.dart';

class VideoRepository {
  VideoRepository({
    required VodApiClient api,
    required ContentFilter filter,
    required EpisodeParser episodeParser,
  })  : _api = api,
        _filter = filter,
        _episodeParser = episodeParser;

  final VodApiClient _api;
  final ContentFilter _filter;
  final EpisodeParser _episodeParser;

  Future<List<VideoItem>> searchAcrossSources({
    required List<VodSource> sources,
    required String query,
    required bool adultFilterEnabled,
    required bool adFilteringEnabled,
    List<AdFilter> adFilters = const [],
    String proxyBaseUrl = '',
    Set<String>? sourceIds,
    bool deduplicate = true,
  }) async {
    final enabled = sources.where((s) {
      if (!s.enabled) return false;
      if (sourceIds == null || sourceIds.isEmpty) return true;
      return sourceIds.contains(s.id);
    }).toList();

    final futures = enabled.map((source) async {
      try {
        return await _api.search(
          baseUrl: source.apiUrl,
          sourceId: source.id,
          query: query,
          proxyBaseUrl: proxyBaseUrl,
        );
      } catch (_) {
        return <VideoItem>[];
      }
    }).toList();

    final chunks = await Future.wait(futures);
    final merged = chunks.expand((e) => e).toList();

    List<VideoItem> dedup = merged;
    if (deduplicate) {
      final seen = <String>{};
      dedup = merged.where((item) {
        final key = item.title.trim().toLowerCase();
        if (seen.contains(key)) return false;
        seen.add(key);
        return true;
      }).toList();
    }

    final visible = _filter.filterVideos(
      dedup,
      adultFilterEnabled: adultFilterEnabled,
    );
    return _filterAdVideos(
      visible,
      adFilteringEnabled: adFilteringEnabled,
      adFilters: adFilters,
    );
  }

  Future<(VideoItem detail, List<EpisodeItem> episodes)> fetchDetail({
    required List<VodSource> sources,
    required VideoItem video,
    required bool adFilteringEnabled,
    List<AdFilter> adFilters = const [],
    String proxyBaseUrl = '',
  }) async {
    final source = sources.firstWhere((s) => s.id == video.sourceId);
    final result = await _api.detail(
      baseUrl: source.apiUrl,
      sourceId: source.id,
      id: video.id,
      proxyBaseUrl: proxyBaseUrl,
    );

    final episodes = _filterAdEpisodes(
      _episodeParser.parse(result.episodesRaw),
      adFilteringEnabled: adFilteringEnabled,
      adFilters: adFilters,
    );
    return (
      _isAdMatch(
        result.video.url,
        adFilteringEnabled: adFilteringEnabled,
        adFilters: adFilters,
      )
          ? result.video.copyWith(url: episodes.isEmpty ? '' : episodes.first.url)
          : result.video,
      episodes,
    );
  }

  Future<int?> probeSourceLatency(VodSource source, {String proxyBaseUrl = ''}) {
    return _api.probeLatency(baseUrl: source.apiUrl, proxyBaseUrl: proxyBaseUrl);
  }

  Future<List<AlternativeSourceCandidate>> findAlternatives({
    required List<VodSource> sources,
    required VideoItem current,
    required bool adultFilterEnabled,
    required bool adFilteringEnabled,
    List<AdFilter> adFilters = const [],
    String proxyBaseUrl = '',
  }) async {
    final enabled = sources
        .where((s) => s.enabled && s.id != current.sourceId)
        .toList();
    final normalizedTarget = _normalizeTitle(current.title);

    final matches = <AlternativeSourceCandidate>[];
    for (final source in enabled) {
      try {
        final candidates = await _api.search(
          baseUrl: source.apiUrl,
          sourceId: source.id,
          query: current.title,
          proxyBaseUrl: proxyBaseUrl,
        );
        final filtered = _filter.filterVideos(
          candidates,
          adultFilterEnabled: adultFilterEnabled,
        );
        final visible = _filterAdVideos(
          filtered,
          adFilteringEnabled: adFilteringEnabled,
          adFilters: adFilters,
        );
        if (visible.isEmpty) continue;

        VideoItem? best;
        for (final item in visible) {
          final n = _normalizeTitle(item.title);
          if (n == normalizedTarget) {
            best = item;
            break;
          }
          if (n.contains(normalizedTarget) || normalizedTarget.contains(n)) {
            best ??= item;
          }
        }

        if (best != null) {
          matches.add(AlternativeSourceCandidate(source: source, video: best));
        }
      } catch (_) {
        continue;
      }
    }
    return matches;
  }

  String _normalizeTitle(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\u4e00-\u9fa5a-z0-9]'), '');
  }

  List<VideoItem> _filterAdVideos(
    List<VideoItem> items, {
    required bool adFilteringEnabled,
    required List<AdFilter> adFilters,
  }) {
    if (!adFilteringEnabled || adFilters.isEmpty) return items;
    return items
        .where(
          (item) => !_isAdMatch(
            item.url,
            adFilteringEnabled: adFilteringEnabled,
            adFilters: adFilters,
          ),
        )
        .toList();
  }

  List<EpisodeItem> _filterAdEpisodes(
    List<EpisodeItem> items, {
    required bool adFilteringEnabled,
    required List<AdFilter> adFilters,
  }) {
    if (!adFilteringEnabled || adFilters.isEmpty) return items;
    return items
        .where(
          (item) => !_isAdMatch(
            item.url,
            adFilteringEnabled: adFilteringEnabled,
            adFilters: adFilters,
          ),
        )
        .toList();
  }

  bool _isAdMatch(
    String value, {
    required bool adFilteringEnabled,
    required List<AdFilter> adFilters,
  }) {
    if (!adFilteringEnabled) return false;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    for (final filter in adFilters) {
      if (!filter.enabled) continue;
      final pattern = filter.pattern.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      if (normalized.contains(pattern)) return true;
    }
    return false;
  }
}
