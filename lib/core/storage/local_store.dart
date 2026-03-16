import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/playback_history_item.dart';
import '../models/video_item.dart';
import '../models/vod_source.dart';

class LocalStore {
  static const _sourcesKey = 'vod_sources';
  static const _favoritesKey = 'favorites';
  static const _historyKey = 'playback_history';
  static const _settingsKey = 'app_settings';
  static const _searchHistoryKey = 'search_history';

  Future<List<VodSource>> loadSources() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_sourcesKey);
    if (raw == null || raw.isEmpty) {
      return _defaultSources;
    }

    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(VodSource.fromJson)
        .toList();
  }

  Future<void> saveSources(List<VodSource> sources) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _sourcesKey,
      jsonEncode(sources.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<VideoItem>> loadFavorites() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_favoritesKey);
    if (raw == null || raw.isEmpty) return const [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>().map(VideoItem.fromJson).toList();
  }

  Future<void> saveFavorites(List<VideoItem> favorites) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _favoritesKey,
      jsonEncode(favorites.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<PlaybackHistoryItem>> loadHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(PlaybackHistoryItem.fromJson)
        .toList();
  }

  Future<void> saveHistory(List<PlaybackHistoryItem> history) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _historyKey,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  Future<AppSettings> loadSettings() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<List<String>> loadSearchHistory() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_searchHistoryKey) ?? const [];
  }

  Future<void> saveSearchHistory(List<String> values) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_searchHistoryKey, values);
  }

  List<VodSource> get _defaultSources => const [
    VodSource(
      id: 'heimuer',
      name: 'HeiMuer',
      apiUrl: 'https://heimuer.tv/api.php/provide/vod/',
      enabled: true,
      isDefault: true,
    ),
    VodSource(
      id: 'bfzy',
      name: 'BFZY',
      apiUrl: 'https://bfzyapi.com/api.php/provide/vod/',
      enabled: false,
      isDefault: true,
    ),
  ];
}
