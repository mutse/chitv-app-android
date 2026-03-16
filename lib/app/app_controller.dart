import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/alternative_source_candidate.dart';
import '../core/models/app_settings.dart';
import '../core/models/episode_item.dart';
import '../core/models/playback_history_item.dart';
import '../core/models/video_item.dart';
import '../core/models/vod_source.dart';
import '../core/storage/local_store.dart';
import 'video_repository.dart';

class AppController extends ChangeNotifier {
  AppController({
    required LocalStore localStore,
    required VideoRepository repository,
  })  : _localStore = localStore,
        _repository = repository;

  final LocalStore _localStore;
  final VideoRepository _repository;

  bool initializing = true;
  bool searching = false;
  bool probingSources = false;
  String? error;

  List<VodSource> sources = const [];
  Map<String, int?> sourceLatencyMs = const {};
  List<VideoItem> searchResults = const [];
  List<VideoItem> favorites = const [];
  List<PlaybackHistoryItem> history = const [];
  AppSettings settings = const AppSettings();
  int qosSessionCount = 0;
  int qosErrorCount = 0;
  int qosBufferEvents = 0;
  int qosBufferTotalMs = 0;
  int qosRetryCount = 0;
  int qosStartupTotalMs = 0;

  Future<void> init() async {
    initializing = true;
    notifyListeners();

    sources = await _localStore.loadSources();
    favorites = await _localStore.loadFavorites();
    history = await _localStore.loadHistory();
    settings = await _localStore.loadSettings();
    await refreshSourceSpeeds(silent: true);

    initializing = false;
    notifyListeners();
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) return;
    searching = true;
    error = null;
    notifyListeners();

    try {
      searchResults = await _repository.searchAcrossSources(
        sources: sources,
        query: query.trim(),
        adultFilterEnabled: settings.adultFilterEnabled,
      );
    } catch (e) {
      error = '$e';
    }

    searching = false;
    notifyListeners();
  }

  Future<(VideoItem detail, List<EpisodeItem> episodes)> loadDetail(VideoItem item) async {
    try {
      final result = await _repository.fetchDetail(sources: sources, video: item);
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

  Future<void> setAdultFilter(bool enabled) async {
    settings = settings.copyWith(adultFilterEnabled: enabled);
    await _localStore.saveSettings(settings);
    notifyListeners();
  }

  Future<void> setAutoPlayNext(bool enabled) async {
    settings = settings.copyWith(autoPlayNext: enabled);
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
    final merged = [
      if (trimmed.isNotEmpty) trimmed,
      ...settings.recentSubtitleUrls.where((u) => u != trimmed),
    ].take(10).toList();

    settings = settings.copyWith(
      defaultSubtitleUrl: trimmed,
      recentSubtitleUrls: merged,
    );
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
      final ms = await _repository.probeSourceLatency(source);
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
    await _localStore.saveSources(sources);
    await refreshSourceSpeeds(silent: true);
    notifyListeners();
  }

  Future<void> deleteSource(String sourceId) async {
    sources = sources.where((e) => e.id != sourceId || e.isDefault).toList();
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
      Map<String, dynamic>.from(decoded['settings'] as Map? ?? <String, dynamic>{}),
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
    }
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
    );

    alternatives.sort((a, b) {
      final ams = sourceLatencyMs[a.source.id] ?? 999999;
      final bms = sourceLatencyMs[b.source.id] ?? 999999;
      return ams.compareTo(bms);
    });
    return alternatives;
  }
}
