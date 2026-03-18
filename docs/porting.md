# LibreTV Flutter 移植技术方案

## 一、整体架构映射

```
LibreTV (Web)          →  Flutter App
─────────────────────────────────────────
index.html             →  SearchPage / HomeScreen
player.html            →  PlayerPage
js/config.js           →  lib/config/api_config.dart
js/app.js              →  lib/services/search_service.dart
js/api.js              →  lib/services/api_service.dart
js/douban.js           →  lib/services/douban_service.dart
localStorage           →  SharedPreferences / Hive
Node.js proxy server   →  后端不变 / 或 Dart HTTP代理
HLS 播放               →  video_player + better_player
```

---

## 二、核心数据结构

### 2.1 视频源 API 站点

```dart
// 对应 js/config.js 中的 API_SITES
class ApiSite {
  final String id;          // 唯一标识, e.g. "heimuer"
  final String name;        // 显示名称, e.g. "黑木耳"
  final String baseUrl;     // e.g. "https://json.heimuer.xyz"
  final bool isBuiltIn;     // true=内置, false=用户自定义
  final bool isEnabled;     // 用户可开关
  final bool isAdult;       // 成人内容标记

  // 完整搜索URL拼接
  String searchUrl(String keyword) =>
    "$baseUrl/api.php/provide/vod/?ac=videolist&wd=${Uri.encodeComponent(keyword)}";

  String detailUrl(String id) =>
    "$baseUrl/api.php/provide/vod/?ac=detail&ids=$id";
}
```

### 2.2 苹果CMS V10 API 响应

```dart
// 标准苹果CMS V10接口响应结构
class VodListResponse {
  final int code;          // 1 = 成功
  final String msg;
  final int page;
  final int pageCount;
  final int limit;
  final int total;
  final List<VodItem> list;
}

class VodItem {
  final int vodId;          // vod_id
  final String name;        // vod_name
  final String pic;         // 封面图URL
  final String type;        // 类型名称
  final String year;
  final String area;
  final String remarks;     // 备注，如"第12集"
  final String content;     // 简介
  final String time;        // 更新时间
  final String sourceId;    // 来源站点ID（移植层附加）

  // 播放源列表：格式 "源名$$$URL###源名$$$URL"
  // 解析后得到 List<PlaySource>
  final String playFrom;    // vod_play_from
  final String playUrl;     // vod_play_url
}

class PlaySource {
  final String sourceName;  // e.g. "线路1"
  final List<Episode> episodes;
}

class Episode {
  final String label;       // e.g. "第01集"
  final String url;         // m3u8/mp4 URL
}
```

### 2.3 聚合搜索配置

```dart
class AggregatedSearchConfig {
  final int timeout;           // 单源超时，默认 8000ms
  final int maxResults;        // 最大结果数，默认 10000
  final bool showSourceBadge;  // 显示来源徽标
  final bool enableParallel;   // 并行请求所有源
}
```

### 2.4 播放历史 & 收藏

```dart
class WatchHistory {
  final String vodId;
  final String sourceSiteId;
  final String vodName;
  final String pic;
  final int lastEpisodeIndex;
  final Duration lastPosition;
  final DateTime updatedAt;
}

class Favorite {
  final String vodId;
  final String sourceSiteId;
  final String vodName;
  final String pic;
  final DateTime savedAt;
}
```

### 2.5 App 全局配置

```dart
class AppConfig {
  final List<ApiSite> sites;
  final bool filterAdult;          // 过滤成人内容
  final bool aggregatedSearch;     // 聚合搜索开关
  final String proxyUrl;           // 后端代理地址
  final String? passwordHash;      // SHA-256 密码哈希
  final PlayerConfig player;
}

class PlayerConfig {
  final bool autoNext;         // 自动播放下集
  final bool adFilter;         // HLS广告过滤
  final String defaultQuality; // "auto" | "1080p" | ...
}
```

---

## 三、核心 API 伪代码

### 3.1 SearchService（对应 app.js）

```dart
class SearchService {

  // 聚合搜索：并行请求所有启用的站点
  Future<List<VodItem>> aggregatedSearch(String keyword) async {
    final enabledSites = config.sites.where((s) => s.isEnabled).toList();

    final futures = enabledSites.map((site) =>
      _searchSingleSite(site, keyword)
        .timeout(Duration(milliseconds: 8000))
        .catchError((_) => <VodItem>[])   // 单站超时不中断整体
    );

    final results = await Future.wait(futures);
    final merged = results.expand((r) => r).toList();

    // 去重 + 成人内容过滤
    return _dedupeAndFilter(merged);
  }

  Future<List<VodItem>> _searchSingleSite(ApiSite site, String keyword) async {
    final url = site.searchUrl(keyword);
    final resp = await apiService.get(url);           // 经后端代理
    final parsed = VodListResponse.fromJson(resp);
    // 附加来源标识
    return parsed.list.map((v) => v.copyWith(sourceId: site.id)).toList();
  }

  List<VodItem> _dedupeAndFilter(List<VodItem> items) {
    // 1. 成人内容过滤（按关键词/类型标记）
    // 2. 按 vodName+year 简单去重，保留评分更高的源
    // 3. 截断至 maxResults
    ...
  }
}
```

### 3.2 ApiService（对应 api.js + server.mjs 代理）

```dart
class ApiService {
  final String proxyBase;  // e.g. "https://your-libretv-server.com"

  // 所有外部请求走后端代理，解决 CORS 和 HTTPS 混合内容问题
  Future<Map<String, dynamic>> get(String targetUrl) async {
    final proxyUrl = "$proxyBase/proxy?url=${Uri.encodeComponent(targetUrl)}";
    final response = await http.get(
      Uri.parse(proxyUrl),
      headers: {"Accept": "application/json"},
    ).timeout(Duration(seconds: 10));

    if (response.statusCode != 200) throw ApiException(response.statusCode);
    return jsonDecode(response.body);
  }

  // HLS 代理：m3u8 内容需重写分片URL为代理路径（广告过滤入口）
  Future<String> fetchM3u8(String m3u8Url) async {
    final proxied = "$proxyBase/hls/proxy?url=${Uri.encodeComponent(m3u8Url)}";
    final response = await http.get(Uri.parse(proxied));
    return response.body; // 已由服务端做广告分片过滤
  }
}
```

### 3.3 DetailService（解析播放列表）

```dart
class DetailService {

  Future<VodItem> fetchDetail(String vodId, ApiSite site) async {
    final url = site.detailUrl(vodId);
    final resp = await apiService.get(url);
    final vod = VodListResponse.fromJson(resp).list.first;
    return _parsePlaySources(vod);
  }

  // 解析 vod_play_from / vod_play_url 为结构化 PlaySource 列表
  // vod_play_from: "线路1$$$线路2"
  // vod_play_url:  "第01集$$$url1###第02集$$$url2$$$$$第01集$$$url1###..."
  VodItem _parsePlaySources(VodItem raw) {
    final froms = raw.playFrom.split(r'$$$');
    final urlGroups = raw.playUrl.split(r'$$$$$');

    final sources = List.generate(froms.length, (i) {
      final eps = urlGroups[i].split('###').map((ep) {
        final parts = ep.split(r'$$$');
        return Episode(label: parts[0], url: parts[1]);
      }).toList();
      return PlaySource(sourceName: froms[i], episodes: eps);
    });

    return raw.copyWith(playSources: sources);
  }
}
```

### 3.4 StorageService（对应 localStorage）

```dart
class StorageService {
  // 使用 Hive 或 SharedPreferences

  Future<void> saveApiSites(List<ApiSite> sites) async { ... }
  Future<List<ApiSite>> loadApiSites() async { ... }

  Future<void> saveHistory(WatchHistory h) async { ... }
  Future<List<WatchHistory>> loadHistory() async { ... }
  Future<void> deleteHistory(String vodId) async { ... }

  Future<void> toggleFavorite(VodItem vod) async { ... }
  Future<bool> isFavorite(String vodId) async { ... }

  Future<void> saveConfig(AppConfig cfg) async { ... }
  Future<AppConfig> loadConfig() async { ... }
}
```

### 3.5 PlayerController（对应 player.html + HLS引擎）

```dart
class PlayerController {
  final better_player.BetterPlayerController _inner;

  // 初始化播放，自动走代理
  Future<void> playEpisode(Episode ep, {Duration? startAt}) async {
    String resolvedUrl = ep.url;

    // m3u8 走代理（服务端广告过滤）
    if (ep.url.contains('.m3u8')) {
      resolvedUrl = apiService.buildHlsProxyUrl(ep.url);
    }

    final source = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      resolvedUrl,
      videoFormat: ep.url.contains('.m3u8')
        ? BetterPlayerVideoFormat.hls
        : BetterPlayerVideoFormat.other,
    );

    await _inner.setupDataSource(source);
    if (startAt != null) await _inner.seekTo(startAt);
    await _inner.play();
  }

  // 切集
  void switchEpisode(Episode next) => playEpisode(next);

  // 保存进度（用于"断点续播"）
  void saveProgress(String vodId, int epIndex) {
    storageService.saveHistory(WatchHistory(
      vodId: vodId,
      lastEpisodeIndex: epIndex,
      lastPosition: _inner.videoPlayerController!.value.position,
      updatedAt: DateTime.now(),
      ...
    ));
  }
}
```

### 3.6 DoubanService（首页热门推荐）

```dart
class DoubanService {

  // 豆瓣热门榜单（LibreTV 用于首页内容发现）
  Future<List<DoubanItem>> fetchHotMovies({int start = 0, int limit = 20}) async {
    final url =
      "https://movie.douban.com/j/search_subjects"
      "?type=movie&tag=热门&sort=recommend&page_limit=$limit&page_start=$start";
    // 同样走后端代理
    final resp = await apiService.get(url);
    return (resp['subjects'] as List)
      .map(DoubanItem.fromJson)
      .toList();
  }

  Future<List<DoubanItem>> fetchHotTVShows({...}) async { ... }
}

class DoubanItem {
  final String title;
  final String cover;
  final double rate;
  final String url;   // 豆瓣详情页，点击后触发搜索
}
```

---

## 四、页面路由结构

```
/                    →  HomeScreen（豆瓣热门 + 搜索入口）
/search?q=xxx        →  SearchResultsPage（聚合结果列表）
/detail/:siteId/:id  →  DetailPage（剧集选择 + 简介）
/player              →  PlayerPage（传入 Episode + VodItem）
/settings            →  SettingsPage（API管理/过滤/代理配置）
/history             →  HistoryPage
/favorites           →  FavoritesPage
```

---

## 五、关键依赖包

| 功能 | 推荐包 |
|------|--------|
| HLS 播放 | `better_player` 或 `media_kit` |
| 本地存储 | `hive` + `hive_flutter` |
| HTTP | `dio`（支持拦截器做代理前缀注入）|
| 状态管理 | `riverpod` 或 `bloc` |
| 路由 | `go_router` |
| 图片缓存 | `cached_network_image` |

---

## 六、后端代理策略（关键差异点）

LibreTV 依赖 Node.js 服务端做两件事，Flutter 移植须保留：

```
1. CORS 代理
   Flutter → 自有后端 /proxy?url=... → 第三方 API
   （直接在 Flutter 中请求第三方API会遇到证书/CORS，
     推荐复用原 LibreTV 的 Node.js server.mjs 不变）

2. HLS 广告过滤
   Flutter → 后端 /hls/proxy?url=... → 服务端重写m3u8
   （过滤广告分片 segment，返回净化后的 m3u8 给播放器）
```

若想纯客户端化，可考虑用 `media_kit` 的自定义 HTTP 头拦截或 Dart Isolate 实现本地 m3u8 重写，但复杂度较高，建议保留后端代理。

---

这套方案完整覆盖了 LibreTV 的数据流、存储层、播放链路和内容聚合逻辑，按此结构编码即可实现功能对等的 Flutter 客户端。