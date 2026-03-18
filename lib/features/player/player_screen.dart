import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/episode_item.dart';
import '../../core/models/video_item.dart';

/// Video player screen that uses `better_player_plus` wrapping `video_player`
/// for native HLS (m3u8) playback — mirroring the HLS streaming approach
/// used by LibreTV's ArtPlayer + HLS.js stack.
///
/// Key features ported from LibreTV player.js:
///   * HLS adaptive bitrate (ExoPlayer on Android / AVPlayer on iOS)
///   * Proxy-based HLS ad-filtering via server-side m3u8 rewrite
///   * Auto-play next episode
///   * Resume from saved position (history tracking every 5 s)
///   * Retry & error recovery
///   * Fullscreen with landscape lock
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.item,
    this.episodes = const [],
    this.currentEpisodeIndex = -1,
    this.seriesTitle,
  });

  final VideoItem item;
  final List<EpisodeItem> episodes;
  final int currentEpisodeIndex;
  final String? seriesTitle;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  BetterPlayerController? _controller;
  bool _loading = true;
  String? _error;
  bool _endHandled = false;
  int _retry = 0;
  bool _showQos = false;
  int _sessionStartupMs = 0;
  Timer? _historyTimer;
  int _lastSavedPosition = -1;
  final Map<String, String> _localFilteredManifestCache = <String, String>{};

  static const Duration _initializeTimeout = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _initialize(widget.item.url);
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _persistHistoryPosition();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _initialize(String url) async {
    final startedAt = DateTime.now();
    final settings = AppScope.read(context).settings;
    setState(() {
      _loading = true;
      _error = null;
      _endHandled = false;
    });

    try {
      // Dispose previous controller if exists.
      _controller?.dispose();
      _controller = null;

      final rawCandidates = _buildRawPlaybackCandidates(url);
      if (rawCandidates.isEmpty) {
        throw Exception('无可用播放地址');
      }

      BetterPlayerController? playerController;
      Object? lastError;

      for (final raw in rawCandidates) {
        final resolved = await _resolvePlaybackUrl(raw, settings);
        final candidates = _buildUrlCandidates(resolved);
        for (final uri in candidates) {
          try {
            playerController = await _createPlayer(
              uri,
              loopPlayback: settings.loopPlayback,
            ).timeout(_initializeTimeout);
            break;
          } catch (e) {
            lastError = e;
          }
        }
        if (playerController != null) break;
      }

      if (playerController == null) {
        throw lastError ?? Exception('播放器初始化失败');
      }

      if (!mounted) {
        playerController.dispose();
        return;
      }

      _controller = playerController;
      _listenToPlayer();

      _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
      AppScope.read(context)
          .recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
      setState(() => _loading = false);

      _startHistoryTracking();
      unawaited(AppScope.read(context).addHistory(widget.item));
    } catch (e) {
      if (!mounted) return;

      if (_retry < 2) {
        _retry += 1;
        AppScope.read(context).recordPlaybackRetry();
        await Future<void>.delayed(Duration(milliseconds: 400 * _retry));
        return _initialize(url);
      }

      AppScope.read(context).recordPlaybackError();
      final msg = e is TimeoutException
          ? '播放超时，请检查网络或代理配置后重试'
          : '播放失败: $e';
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  /// Create a [BetterPlayerController] pre-configured for HLS playback.
  ///
  /// This mirrors LibreTV's HLS.js configuration:
  ///   - adaptive bitrate (startLevel: -1 → auto)
  ///   - retry on network / media errors
  ///   - buffering parameters comparable to HLS.js defaults
  Future<BetterPlayerController> _createPlayer(
    Uri uri, {
    required bool loopPlayback,
  }) async {
    final isHls = _isHlsUrl(uri.toString());

    // ── BetterPlayerConfiguration ──
    // Comparable to the ArtPlayer options in LibreTV (autoplay, controls, etc.)
    final configuration = BetterPlayerConfiguration(
      autoPlay: true,
      looping: loopPlayback,
      aspectRatio: 16 / 9,
      fit: BoxFit.contain,
      handleLifecycle: true,
      autoDetectFullscreenAspectRatio: true,
      autoDetectFullscreenDeviceOrientation: true,
      allowedScreenSleep: false,
      // Enter fullscreen in landscape, matching LibreTV behavior.
      deviceOrientationsOnFullScreen: const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      controlsConfiguration: BetterPlayerControlsConfiguration(
        enablePlayPause: true,
        enableMute: true,
        enableProgressBar: true,
        enableProgressText: true,
        enableFullscreen: true,
        enableSkips: true,
        enablePlaybackSpeed: true,
        enableQualities: isHls, // Show quality selector only for HLS.
        enableAudioTracks: isHls,
        overflowMenuCustomItems: const [],
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      // Error widget — mirrors the "⚠️ 视频加载失败" from player.html.
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 48),
              const SizedBox(height: 12),
              Text(
                '视频加载失败',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                '请尝试其他视频源或稍后重试',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );

    // ── BetterPlayerDataSource ──
    // For HLS (.m3u8) we set videoFormat to hls so that ExoPlayer / AVPlayer
    // handles adaptive bitrate switching — same concept as HLS.js in browser.
    final isLocalFile = uri.scheme == 'file';
    final headers = isLocalFile ? const <String, String>{} : _buildPlaybackHeaders(uri);
    final dataSource = BetterPlayerDataSource(
      isLocalFile
          ? BetterPlayerDataSourceType.file
          : BetterPlayerDataSourceType.network,
      isLocalFile ? uri.toFilePath() : uri.toString(),
      videoFormat:
          isHls ? BetterPlayerVideoFormat.hls : BetterPlayerVideoFormat.other,
      headers: headers,
      // Cache configuration — allows buffering ahead.
      cacheConfiguration: const BetterPlayerCacheConfiguration(
        useCache: true,
        maxCacheSize: 100 * 1024 * 1024, // 100 MB cache
        maxCacheFileSize: 20 * 1024 * 1024, // 20 MB per file
      ),
      // Buffer configuration mirroring HLS.js settings from LibreTV:
      //   maxBufferLength: 30, backBufferLength: 90
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        minBufferMs: 10000,
        maxBufferMs: 60000,
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
      // Notification configuration (for background / PiP playback).
      notificationConfiguration: BetterPlayerNotificationConfiguration(
        showNotification: false,
        title: widget.item.title,
        author: 'ChiTV',
      ),
    );

    final controller = BetterPlayerController(
      configuration,
      betterPlayerDataSource: dataSource,
    );

    // Wait for the player to be initialized.
    final completer = Completer<BetterPlayerController>();

    void checkInitialized() {
      final vp = controller.videoPlayerController;
      if (vp != null && vp.value.initialized) {
        completer.complete(controller);
      }
    }

    // Listen for events to know when ready.
    controller.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
        if (!completer.isCompleted) {
          completer.complete(controller);
        }
      }
      if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception(event.parameters?['exception'] ?? '播放器异常'),
          );
        }
      }
    });

    // Also check immediately in case it's already initialized.
    checkInitialized();

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Player event listening
  // ---------------------------------------------------------------------------

  void _listenToPlayer() {
    final c = _controller;
    if (c == null) return;

    c.addEventsListener((event) {
      if (!mounted) return;

      switch (event.betterPlayerEventType) {
        case BetterPlayerEventType.finished:
          if (!_endHandled) {
            _endHandled = true;
            _playNextIfNeeded();
          }
          break;

        case BetterPlayerEventType.exception:
          debugPrint('[PlayerScreen] Player error: ${event.parameters}');
          setState(() {});
          break;

        case BetterPlayerEventType.play:
        case BetterPlayerEventType.pause:
          setState(() {});
          break;

        case BetterPlayerEventType.bufferingStart:
          // Track buffering for QoS.
          AppScope.read(context).recordBufferEvent(durationMs: 0);
          break;

        case BetterPlayerEventType.progress:
          if (_showQos && mounted) setState(() {});
          break;

        default:
          break;
      }
    });
  }

  void _playNextIfNeeded() {
    final app = AppScope.read(context);
    if (!app.settings.autoPlayNext) return;

    final nextIndex = widget.currentEpisodeIndex + 1;
    if (widget.currentEpisodeIndex < 0 ||
        nextIndex >= widget.episodes.length) {
      return;
    }

    _openEpisode(nextIndex);
  }

  // ---------------------------------------------------------------------------
  // History tracking (every 5 s)
  // ---------------------------------------------------------------------------

  void _startHistoryTracking() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistHistoryPosition();
    });
  }

  void _persistHistoryPosition() {
    final c = _controller;
    if (c == null) return;
    final vp = c.videoPlayerController;
    if (vp == null) return;

    final seconds = vp.value.position.inSeconds;
    if (seconds < 0 || seconds == _lastSavedPosition) return;
    _lastSavedPosition = seconds;
    unawaited(
      AppScope.read(context).addHistory(widget.item, positionSeconds: seconds),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title),
        actions: [
          // Engine badge
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'BetterPlayer',
                  style: TextStyle(fontSize: 10, color: Colors.blue),
                ),
              ),
            ),
          ),
          if (app.settings.subtitleEnabled &&
              app.settings.defaultSubtitleUrl.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: Text('字幕已启用')),
            ),
          IconButton(
            onPressed: () => setState(() => _showQos = !_showQos),
            icon: const Icon(Icons.query_stats),
            tooltip: 'QoS',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            _retry = 0;
                            _initialize(widget.item.url);
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Player area
                    Expanded(
                      child: Center(child: _buildPlayer(app)),
                    ),
                    // Episode navigation (prev / next)
                    if (widget.currentEpisodeIndex >= 0 &&
                        widget.episodes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            OutlinedButton(
                              onPressed: widget.currentEpisodeIndex > 0
                                  ? () => _openEpisode(
                                      widget.currentEpisodeIndex - 1)
                                  : null,
                              child: const Text('上一集'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '第 ${widget.currentEpisodeIndex + 1} / ${widget.episodes.length} 集',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: widget.currentEpisodeIndex <
                                      widget.episodes.length - 1
                                  ? () => _openEpisode(
                                      widget.currentEpisodeIndex + 1)
                                  : null,
                              child: const Text('下一集'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildPlayer(AppController app) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();

    return Stack(
      children: [
        BetterPlayer(controller: c),
        if (_showQos) _buildQosPanel(app),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Episode switching
  // ---------------------------------------------------------------------------

  void _openEpisode(int index) {
    _persistHistoryPosition();
    final ep = widget.episodes[index];
    final title = widget.seriesTitle ?? widget.item.title;
    final next = VideoItem(
      id: widget.item.id,
      title: '$title ${ep.name}',
      description: widget.item.description,
      poster: widget.item.poster,
      url: ep.url,
      sourceId: widget.item.sourceId,
      vodPlayUrl: widget.item.vodPlayUrl,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          item: next,
          episodes: widget.episodes,
          currentEpisodeIndex: index,
          seriesTitle: title,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // QoS Overlay
  // ---------------------------------------------------------------------------

  Widget _buildQosPanel(AppController app) {
    final c = _controller;
    final vp = c?.videoPlayerController;
    final pos = vp?.value.position ?? Duration.zero;
    final dur = vp?.value.duration ?? Duration.zero;
    final isBuffering = vp?.value.isBuffering ?? false;

    return Positioned(
      left: 10,
      top: 10,
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('QoS Monitor',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('引擎: BetterPlayer (video_player + ExoPlayer)'),
              Text('本次启动: ${_sessionStartupMs}ms'),
              Text('累计会话: ${app.qosSessionCount}'),
              Text('平均启动: ${app.qosAvgStartupMs}ms'),
              Text('缓冲次数: ${app.qosBufferEvents}'),
              Text('缓冲总时长: ${app.qosBufferTotalMs}ms'),
              Text('重试次数: ${app.qosRetryCount}'),
              Text('错误次数: ${app.qosErrorCount}'),
              Text('正在缓冲: $isBuffering'),
              Text('位置: ${pos.inSeconds}s / ${dur.inSeconds}s'),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // URL resolution helpers (same as before)
  // ---------------------------------------------------------------------------

  List<Uri> _buildUrlCandidates(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return const [];

    final values = <String>[
      normalized,
      normalized.replaceAll(r'\/', '/'),
      if (normalized.startsWith('//')) 'https:$normalized',
    ];

    final unique = <String>{};
    final result = <Uri>[];
    for (final value in values) {
      if (value.isEmpty || unique.contains(value)) continue;
      unique.add(value);

      final parsed = Uri.tryParse(value);
      if (parsed != null &&
          parsed.hasScheme &&
          (parsed.host.isNotEmpty || parsed.scheme == 'file')) {
        result.add(parsed);
      }

      final encodedValue = Uri.encodeFull(value);
      if (!unique.contains(encodedValue)) {
        unique.add(encodedValue);
        final encodedParsed = Uri.tryParse(encodedValue);
        if (encodedParsed != null &&
            encodedParsed.hasScheme &&
            (encodedParsed.host.isNotEmpty || encodedParsed.scheme == 'file')) {
          result.add(encodedParsed);
        }
      }
    }

    return result;
  }

  /// Resolve HLS proxy URL if ad-filtering is enabled.
  ///
  /// This mirrors LibreTV's ApiService.fetchM3u8 which routes m3u8 through
  /// the server proxy at `/hls/proxy?url=...` for ad-segment filtering.
  Future<String> _resolvePlaybackUrl(String rawUrl, AppSettings settings) async {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty) return normalized;

    if (!_isHlsUrl(normalized)) return normalized;
    if (!settings.hlsAdFilterEnabled) return normalized;

    final proxyBase = settings.hlsProxyBaseUrl.trim().isNotEmpty
        ? settings.hlsProxyBaseUrl.trim()
        : settings.proxyBaseUrl.trim();
    if (proxyBase.isEmpty) {
      return _buildLocalFilteredManifest(normalized);
    }

    final baseUri = Uri.tryParse(proxyBase);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      return _buildLocalFilteredManifest(normalized);
    }

    final existingUri = Uri.tryParse(normalized);
    if (existingUri != null &&
        existingUri.hasScheme &&
        existingUri.host == baseUri.host &&
        existingUri.path.contains('/hls/proxy')) {
      return normalized;
    }

    final proxyPath = _joinPath(baseUri.path, '/hls/proxy');
    final query = <String, String>{
      ...baseUri.queryParameters,
      'url': normalized,
    };

    return baseUri.replace(path: proxyPath, queryParameters: query).toString();
  }

  bool _isHlsUrl(String value) {
    final lower = value.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('type=m3u8') ||
        lower.endsWith('m3u');
  }

  String _joinPath(String left, String right) {
    final l = left.endsWith('/') ? left.substring(0, left.length - 1) : left;
    final r = right.startsWith('/') ? right : '/$right';
    return '$l$r';
  }

  Future<String> _buildLocalFilteredManifest(String sourceUrl) async {
    if (_localFilteredManifestCache.containsKey(sourceUrl)) {
      return _localFilteredManifestCache[sourceUrl]!;
    }

    final sourceUri = Uri.tryParse(sourceUrl);
    if (sourceUri == null || !sourceUri.hasScheme || sourceUri.host.isEmpty) {
      return sourceUrl;
    }

    try {
      final response = await http
          .get(
            sourceUri,
            headers: _buildPlaybackHeaders(sourceUri),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return sourceUrl;

      final body = response.body;
      if (!body.trimLeft().startsWith('#EXTM3U')) return sourceUrl;

      final filtered = _filterAdsFromM3u8(body, sourceUri);
      if (filtered.trim().isEmpty) return sourceUrl;

      final file = File(
        '${Directory.systemTemp.path}/chitv_filtered_${DateTime.now().microsecondsSinceEpoch}.m3u8',
      );
      await file.writeAsString(filtered, flush: true);

      final localUri = file.uri.toString();
      _localFilteredManifestCache[sourceUrl] = localUri;
      return localUri;
    } catch (_) {
      return sourceUrl;
    }
  }

  String _filterAdsFromM3u8(String content, Uri sourceUri) {
    final lines = content.split('\n');
    final output = <String>[];
    final base = sourceUri.resolve('./');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        output.add(rawLine);
        continue;
      }

      // 对齐 LibreTV 规则：去掉 #EXT-X-DISCONTINUITY 行。
      if (line.contains('#EXT-X-DISCONTINUITY')) {
        continue;
      }

      if (line.startsWith('#EXT-X-KEY') || line.startsWith('#EXT-X-MAP')) {
        output.add(_rewriteUriAttribute(line, base));
        continue;
      }

      if (line.startsWith('#')) {
        output.add(rawLine);
        continue;
      }

      output.add(base.resolve(line).toString());
    }

    return output.join('\n');
  }

  String _rewriteUriAttribute(String line, Uri base) {
    final re = RegExp(r'URI="([^"]+)"');
    final match = re.firstMatch(line);
    if (match == null) return line;

    final original = match.group(1) ?? '';
    if (original.isEmpty) return line;
    final rewritten = base.resolve(original).toString();
    return line.replaceFirst('URI="$original"', 'URI="$rewritten"');
  }

  /// Build HTTP headers for playback.
  ///
  /// These headers mimic a browser request (matching what LibreTV's HLS.js
  /// would send) so that CDNs accept the request.
  Map<String, String> _buildPlaybackHeaders(Uri uri) {
    final origin = uri.hasScheme && uri.host.isNotEmpty
        ? '${uri.scheme}://${uri.host}'
        : '';
    final referer = origin.isEmpty ? '' : '$origin/';

    return {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      if (origin.isNotEmpty) 'Origin': origin,
      if (referer.isNotEmpty) 'Referer': referer,
    };
  }

  List<String> _buildRawPlaybackCandidates(String primary) {
    final result = <String>[];
    final seen = <String>{};

    void add(String value) {
      final next = value.trim();
      if (next.isEmpty || seen.contains(next)) return;
      seen.add(next);
      result.add(next);
    }

    add(primary);
    for (final alt in _extractSameEpisodeAlternativeUrls()) {
      add(alt);
    }

    return result;
  }

  List<String> _extractSameEpisodeAlternativeUrls() {
    final raw = widget.item.vodPlayUrl?.trim() ?? '';
    if (raw.isEmpty) return const [];

    final targetIndex =
        widget.currentEpisodeIndex >= 0 ? widget.currentEpisodeIndex : 0;
    final output = <String>[];

    final sources = raw.split(r'$$$');
    for (final source in sources) {
      final s = source.trim();
      if (s.isEmpty) continue;
      final delimiter = s.contains('#') ? '#' : '|';
      final entries = s
          .split(delimiter)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (entries.isEmpty) continue;

      final episodeEntry =
          targetIndex < entries.length ? entries[targetIndex] : entries.first;
      final parsed = _extractPlayableFromEpisodeEntry(episodeEntry);
      if (parsed.isNotEmpty) {
        output.add(parsed);
      }
    }

    return output;
  }

  String _extractPlayableFromEpisodeEntry(String entry) {
    if (entry.isEmpty) return '';
    final normalized = entry.split('\u0004').last.trim();
    if (normalized.isEmpty) return '';

    final splitAt = normalized.indexOf(r'$');
    var url =
        splitAt == -1 ? normalized : normalized.substring(splitAt + 1).trim();

    url = url.replaceAll(r'\/', '/');
    if (url.startsWith('//')) {
      url = 'https:$url';
    }

    final lower = url.toLowerCase();
    if (lower.startsWith('http%3a') || lower.startsWith('https%3a')) {
      try {
        url = Uri.decodeFull(url);
      } catch (_) {
        return url;
      }
    }

    return url;
  }
}
