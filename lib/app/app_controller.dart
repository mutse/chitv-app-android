import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/alternative_source_candidate.dart';
import '../core/models/ad_filter.dart';
import '../core/models/app_settings.dart';
import '../core/models/douban_item.dart';
import '../core/models/episode_item.dart';
import '../core/models/playback_history_item.dart';
import '../core/models/video_item.dart';
import '../core/models/vod_source.dart';
import '../core/storage/douban_api_client.dart';
import '../core/storage/local_store.dart';
import 'video_repository.dart';

class AppController extends ChangeNotifier {
  AppController({
    required LocalStore localStore,
    required VideoRepository repository,
    required DoubanApiClient doubanApi,
  }) : _localStore = localStore,
       _repository = repository,
       _doubanApi = doubanApi;

  final LocalStore _localStore;
  final VideoRepository _repository;
  final DoubanApiClient _doubanApi;

  bool initializing = true;
  bool searching = false;
  bool loadingHome = false;
  bool probingSources = false;
  String? error;

  List<VideoItem> homeVideos = const [];
  List<VodSource> sources = const [];
  Map<String, int?> sourceLatencyMs = const {};
  List<VideoItem> searchResults = const [];
  List<DoubanItem> doubanHotMovies = const [];
  List<DoubanItem> doubanHotTvShows = const [];
  bool loadingDoubanHot = false;
  List<VideoItem> favorites = const [];
  List<PlaybackHistoryItem> history = const [];
  AppSettings settings = const AppSettings();
  List<String> recentSearches = const [];
  int qosSessionCount = 0;
  int qosErrorCount = 0;
  int qosBufferEvents = 0;
  int qosBufferTotalMs = 0;
  int qosRetryCount = 0;
  int qosStartupTotalMs = 0;
  int _searchRequestSerial = 0;
  int _sourceMutationVersion = 0;
  int _contentMutationVersion = 0;
  int _homeDisplayMutationVersion = 0;

  int get sourceMutationVersion => _sourceMutationVersion;
  int get contentMutationVersion => _contentMutationVersion;
  int get homeDisplayMutationVersion => _homeDisplayMutationVersion;

  Future<void> init() async {
    initializing = true;
    notifyListeners();

    try {
      final loaded = await Future.wait<Object>([
        _localStore.loadSources(),
        _localStore.loadFavorites(),
        _localStore.loadHistory(),
        _localStore.loadSettings(),
        _localStore.loadSearchHistory(),
      ]);

      sources = loaded[0] as List<VodSource>;
      favorites = loaded[1] as List<VideoItem>;
      history = loaded[2] as List<PlaybackHistoryItem>;
      settings = loaded[3] as AppSettings;
      recentSearches = loaded[4] as List<String>;
    } catch (e) {
      error = '初始化失败: $e';
    }

    initializing = false;
    notifyListeners();

    unawaited(_warmUpHomeResources());
  }

  Future<void> _warmUpHomeResources() async {
    try {
      await Future.wait<void>([
        loadHomeVideos(),
        refreshSourceSpeeds(silent: true),
        loadDoubanHot(silent: true),
      ]);
    } catch (_) {
      // Warm-up runs in background; UI remains usable even when it fails.
    }
  }

  Future<void> search(String query, {Set<String>? sourceIds}) async {
    if (query.trim().isEmpty) return;
    final requestSerial = ++_searchRequestSerial;
    searching = true;
    error = null;
    notifyListeners();

    try {
      final results = await _repository.searchAcrossSources(
        sources: sources,
        query: query.trim(),
        adultFilterEnabled: settings.adultFilterEnabled,
        adFilteringEnabled: settings.hlsAdFilterEnabled,
        adFilters: settings.adFilters,
        proxyBaseUrl: settings.proxyBaseUrl,
        sourceIds: sourceIds,
      );
      if (requestSerial != _searchRequestSerial) return;
      searchResults = results;
      await _saveSearchHistory(query.trim());
    } catch (e) {
      if (requestSerial != _searchRequestSerial) return;
      error = '$e';
    }

    if (requestSerial != _searchRequestSerial) return;
    searching = false;
    notifyListeners();
  }

  void clearSearchState() {
    _searchRequestSerial += 1;
    searching = false;
    error = null;
    searchResults = const [];
    notifyListeners();
  }

  Future<void> loadHomeVideos({Set<String>? sourceIds}) async {
    loadingHome = true;
    notifyListeners();

    try {
      homeVideos = await _repository.searchAcrossSources(
        sources: sources,
        query: '',
        adultFilterEnabled: settings.adultFilterEnabled,
        adFilteringEnabled: settings.hlsAdFilterEnabled,
        adFilters: settings.adFilters,
        proxyBaseUrl: settings.proxyBaseUrl,
        sourceIds: sourceIds,
      );
    } catch (_) {
      homeVideos = const [];
    }

    loadingHome = false;
    notifyListeners();
  }

  Future<void> loadDoubanHot({bool silent = false}) async {
    if (!settings.doubanHotEnabled) {
      doubanHotMovies = const [];
      doubanHotTvShows = const [];
      loadingDoubanHot = false;
      notifyListeners();
      return;
    }

    if (!silent) {
      loadingDoubanHot = true;
      notifyListeners();
    }

    try {
      final result = await Future.wait<List<DoubanItem>>([
        _doubanApi.fetchHotMovies(
          proxyBaseUrl: settings.proxyBaseUrl,
          endpoint: settings.doubanHotEndpoint,
        ),
        _doubanApi.fetchHotTvShows(
          proxyBaseUrl: settings.proxyBaseUrl,
          endpoint: settings.doubanHotEndpoint,
        ),
      ]);
      doubanHotMovies = result[0];
      doubanHotTvShows = result[1];
    } catch (_) {
      doubanHotMovies = const [];
      doubanHotTvShows = const [];
    }

    loadingDoubanHot = false;
    notifyListeners();
  }

  Future<(VideoItem detail, List<EpisodeItem> episodes)> loadDetail(
    VideoItem item,
  ) async {
    try {
      final result = await _repository.fetchDetail(
        sources: sources,
        video: item,
        adFilteringEnabled: settings.hlsAdFilterEnabled,
        adFilters: settings.adFilters,
        proxyBaseUrl: settings.proxyBaseUrl,
      );
      return (result.$1, result.$2);
    } catch (_) {
      return (item, <EpisodeItem>[]);
    }
  }

  bool isFavorite(String id) => favorites.any((v) => v.id == id);

  Future<void> toggleFavorite(VideoItem item) async {
    if (isFavorite(item.id)) {
      favorites = favorites.where((v) => v.id != item.id).toList();
    } else {
      favorites = [item, ...favorites];
    }
    await _localStore.saveFavorites(favorites);
    notifyListeners();
  }

  Future<void> addHistory(VideoItem item, {int positionSeconds = 0}) async {
    history = history.where((e) => e.video.id != item.id).toList();
    history = [
      PlaybackHistoryItem(
        video: item,
        watchedAt: DateTime.now(),
        lastPositionSeconds: positionSeconds,
      ),
      ...history,
    ];

    if (history.length > 100) {
      history = history.take(100).toList();
    }

    await _localStore.saveHistory(history);
    notifyListeners();
  }

  PlaybackHistoryItem? findHistoryForVideo(VideoItem item) {
    PlaybackHistoryItem? fallback;
    for (final entry in history) {
      final sameSource = entry.video.sourceId == item.sourceId;
      if (!sameSource) continue;

      if (item.url.isNotEmpty && entry.video.url == item.url) {
        return entry;
      }
      if (fallback == null && entry.video.id == item.id) {
        fallback = entry;
      }
    }
    if (fallback != null) {
      return fallback;
    }
    return null;
  }

  Future<void> setAdultFilter(bool enabled) async {
    settings = settings.copyWith(adultFilterEnabled: enabled);
    _contentMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setAutoPlayNext(bool enabled) async {
    settings = settings.copyWith(autoPlayNext: enabled);
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setLoopPlayback(bool enabled) async {
    settings = settings.copyWith(loopPlayback: enabled);
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setSubtitleEnabled(bool enabled) async {
    settings = settings.copyWith(subtitleEnabled: enabled);
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setDefaultSubtitleUrl(String url) async {
    final trimmed = url.trim();
    final merged = _mergeSubtitleUrls(trimmed);

    settings = settings.copyWith(
      defaultSubtitleUrl: trimmed,
      recentSubtitleUrls: merged,
    );
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> rememberSubtitleUrl(
    String url, {
    bool makeDefault = false,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    settings = settings.copyWith(
      defaultSubtitleUrl: makeDefault ? trimmed : settings.defaultSubtitleUrl,
      recentSubtitleUrls: _mergeSubtitleUrls(trimmed),
    );
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  List<String> _mergeSubtitleUrls(String trimmed) {
    return [
      if (trimmed.isNotEmpty) trimmed,
      ...settings.recentSubtitleUrls.where((u) => u != trimmed),
    ].take(10).toList();
  }

  Future<void> setHlsProxyBaseUrl(String value) async {
    settings = settings.copyWith(hlsProxyBaseUrl: value.trim());
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setHlsAdFilterEnabled(bool enabled) async {
    settings = settings.copyWith(hlsAdFilterEnabled: enabled);
    _contentMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> addAdFilter({
    required String pattern,
    required AdFilterType type,
  }) async {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return;

    final next = [
      AdFilter(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        pattern: trimmed,
        type: type,
      ),
      ...settings.adFilters.where(
        (item) =>
            item.pattern.trim().toLowerCase() != trimmed.toLowerCase() ||
            item.type != type,
      ),
    ];

    settings = settings.copyWith(adFilters: next);
    _contentMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> removeAdFilter(String id) async {
    settings = settings.copyWith(
      adFilters: settings.adFilters.where((item) => item.id != id).toList(),
    );
    _contentMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> toggleAdFilter(String id, bool enabled) async {
    settings = settings.copyWith(
      adFilters: settings.adFilters
          .map((item) => item.id == id ? item.copyWith(enabled: enabled) : item)
          .toList(),
    );
    _contentMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setProxyBaseUrl(String value) async {
    settings = settings.copyWith(proxyBaseUrl: value.trim());
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
    unawaited(loadDoubanHot(silent: true));
    unawaited(refreshSourceSpeeds(silent: true));
  }

  Future<void> setDoubanHotEnabled(bool enabled) async {
    settings = settings.copyWith(doubanHotEnabled: enabled);
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
    unawaited(loadDoubanHot(silent: true));
  }

  Future<void> setDoubanHotEndpoint(String value) async {
    final endpoint = value.trim().isEmpty
        ? AppSettings.defaultDoubanHotEndpoint
        : value.trim();
    settings = settings.copyWith(doubanHotEndpoint: endpoint);
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSettings(settings);
    notifyListeners();
    unawaited(loadDoubanHot(silent: true));
  }

  Future<void> setAppThemeMode(String value) async {
    const allowed = <String>{'system', 'light', 'dark'};
    final mode = allowed.contains(value) ? value : 'system';
    settings = settings.copyWith(appThemeMode: mode);
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> refreshSourceSpeeds({bool silent = false}) async {
    if (!silent) {
      probingSources = true;
      notifyListeners();
    }

    final next = <String, int?>{};
    for (final source in sources) {
      final ms = await _repository.probeSourceLatency(
        source,
        proxyBaseUrl: settings.proxyBaseUrl,
      );
      next[source.id] = ms;
    }

    sourceLatencyMs = next;
    probingSources = false;
    notifyListeners();
  }

  Future<void> upsertSource(VodSource source) async {
    final idx = sources.indexWhere((e) => e.id == source.id);
    if (idx == -1) {
      sources = [...sources, source];
    } else {
      final next = [...sources];
      next[idx] = source;
      sources = next;
    }
    _sourceMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    notifyListeners();
    await _localStore.saveSources(sources);
    await refreshSourceSpeeds(silent: true);
  }

  Future<void> deleteSource(String sourceId) async {
    sources = sources.where((e) => e.id != sourceId || e.isDefault).toList();
    _sourceMutationVersion += 1;
    _homeDisplayMutationVersion += 1;
    await _localStore.saveSources(sources);
    await refreshSourceSpeeds(silent: true);
    notifyListeners();
  }

  String exportConfigurationJson() {
    final payload = <String, dynamic>{
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings.toJson(),
      'sources': sources.map((e) => e.toJson()).toList(),
      'favorites': favorites.map((e) => e.toJson()).toList(),
      'history': history.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> importConfigurationJson(String raw) async {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    final nextSettings = AppSettings.fromJson(
      Map<String, dynamic>.from(
        decoded['settings'] as Map? ?? <String, dynamic>{},
      ),
    );
    final nextSources = (decoded['sources'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(VodSource.fromJson)
        .toList();
    final nextFavorites = (decoded['favorites'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(VideoItem.fromJson)
        .toList();
    final nextHistory = (decoded['history'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(PlaybackHistoryItem.fromJson)
        .toList();

    settings = nextSettings;
    if (nextSources.isNotEmpty) {
      sources = nextSources;
      _sourceMutationVersion += 1;
    }
    _homeDisplayMutationVersion += 1;
    favorites = nextFavorites;
    history = nextHistory;

    await _localStore.saveSettings(settings);
    await _localStore.saveSources(sources);
    await _localStore.saveFavorites(favorites);
    await _localStore.saveHistory(history);
    await refreshSourceSpeeds(silent: true);
    notifyListeners();
  }

  void recordPlaybackSessionStarted({required int startupMs}) {
    qosSessionCount += 1;
    qosStartupTotalMs += startupMs;
    notifyListeners();
  }

  void recordPlaybackRetry() {
    qosRetryCount += 1;
    notifyListeners();
  }

  void recordPlaybackError() {
    qosErrorCount += 1;
    notifyListeners();
  }

  void recordBufferEvent({required int durationMs}) {
    qosBufferEvents += 1;
    qosBufferTotalMs += durationMs;
    notifyListeners();
  }

  void resetQosStats() {
    qosSessionCount = 0;
    qosErrorCount = 0;
    qosBufferEvents = 0;
    qosBufferTotalMs = 0;
    qosRetryCount = 0;
    qosStartupTotalMs = 0;
    notifyListeners();
  }

  int get qosAvgStartupMs =>
      qosSessionCount == 0 ? 0 : (qosStartupTotalMs / qosSessionCount).round();

  Future<List<AlternativeSourceCandidate>> searchAlternativeSources(
    VideoItem current,
  ) async {
    final alternatives = await _repository.findAlternatives(
      sources: sources,
      current: current,
      adultFilterEnabled: settings.adultFilterEnabled,
      adFilteringEnabled: settings.hlsAdFilterEnabled,
      adFilters: settings.adFilters,
      proxyBaseUrl: settings.proxyBaseUrl,
    );

    alternatives.sort((a, b) {
      final ams = sourceLatencyMs[a.source.id] ?? 999999;
      final bms = sourceLatencyMs[b.source.id] ?? 999999;
      return ams.compareTo(bms);
    });
    return alternatives;
  }

  Future<void> _saveSearchHistory(String query) async {
    final next = [
      query,
      ...recentSearches.where((e) => e != query),
    ].take(12).toList();
    recentSearches = next;
    await _localStore.saveSearchHistory(next);
  }

  Future<void> clearSearchHistory() async {
    recentSearches = const [];
    await _localStore.saveSearchHistory(const []);
    notifyListeners();
  }

  Future<void> clearWatchHistory() async {
    history = const [];
    await _localStore.saveHistory(const []);
    notifyListeners();
  }

  Future<void> clearFavorites() async {
    favorites = const [];
    await _localStore.saveFavorites(const []);
    notifyListeners();
  }
}
