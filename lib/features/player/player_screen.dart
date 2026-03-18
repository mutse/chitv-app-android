import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/episode_item.dart';
import '../../core/models/video_item.dart';

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
  /// Unique player ID – we use the hash of the widget to avoid collisions.
  static int _nextPlayerId = 1;

  NativeVideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  bool _endHandled = false;
  int _retry = 0;
  bool _showQos = false;
  int _sessionStartupMs = 0;
  Timer? _historyTimer;
  int _lastSavedPosition = -1;

  /// Subscriptions to player streams.
  StreamSubscription<PlayerActivityState>? _activitySub;
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _initialize(widget.item.url);
  }

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
      await _disposeController();

      final rawCandidates = _buildRawPlaybackCandidates(url);
      if (rawCandidates.isEmpty) {
        throw Exception('无可用播放地址');
      }

      NativeVideoPlayerController? controller;
      Object? lastError;

      for (final raw in rawCandidates) {
        final resolved = _resolvePlaybackUrl(raw, settings);
        final candidates = _buildUrlCandidates(resolved);
        for (final uri in candidates) {
          NativeVideoPlayerController? next;
          try {
            final playerId = _nextPlayerId++;
            next = NativeVideoPlayerController(
              id: playerId,
              autoPlay: true,
              showNativeControls: true,
            );

            await next.initialize().timeout(const Duration(seconds: 8));
            await next
                .loadUrl(
                  url: uri.toString(),
                  headers: _buildPlaybackHeaders(uri),
                )
                .timeout(const Duration(seconds: 12));

            controller = next;
            break;
          } catch (e) {
            try {
              await next?.dispose();
            } catch (_) {}
            lastError = e;
          }
        }
        if (controller != null) {
          break;
        }
      }

      if (controller == null) {
        throw lastError ?? Exception('播放器初始化失败');
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      _listenToPlayer();

      _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
      AppScope.read(context).recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
      setState(() {
        _loading = false;
      });

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
      setState(() {
        _loading = false;
        _error = '播放失败: $e';
      });
    }
  }

  /// Subscribe to player activity and position streams.
  void _listenToPlayer() {
    final c = _controller;
    if (c == null) return;

    _activitySub = c.playerStateStream.listen((state) {
      if (!mounted) return;

      if (state == PlayerActivityState.completed && !_endHandled) {
        _endHandled = true;
        _playNextIfNeeded();
      }

      if (state == PlayerActivityState.error) {
        debugPrint('[PlayerScreen] Player error detected');
        // Trigger rebuild so QoS panel can update.
        setState(() {});
      }

      // Trigger rebuild for play/pause state changes.
      if (state == PlayerActivityState.playing ||
          state == PlayerActivityState.paused) {
        setState(() {});
      }
    });

    _positionSub = c.positionStream.listen((pos) {
      // Position stream is used for history tracking (handled by timer),
      // but we can trigger a rebuild if QoS panel is visible.
      if (_showQos && mounted) {
        setState(() {});
      }
    });
  }

  void _playNextIfNeeded() {
    final app = AppScope.read(context);
    if (!app.settings.autoPlayNext) return;

    final nextIndex = widget.currentEpisodeIndex + 1;
    if (widget.currentEpisodeIndex < 0 || nextIndex >= widget.episodes.length) return;

    _openEpisode(nextIndex);
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _persistHistoryPosition();
    _activitySub?.cancel();
    _positionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _disposeController() async {
    _activitySub?.cancel();
    _activitySub = null;
    _positionSub?.cancel();
    _positionSub = null;
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
  }

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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Native',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
          ),
          if (app.settings.subtitleEnabled && app.settings.defaultSubtitleUrl.isNotEmpty)
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
                    Expanded(
                      child: Center(
                        child: _buildPlayer(app),
                      ),
                    ),
                    if (widget.currentEpisodeIndex >= 0 && widget.episodes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            OutlinedButton(
                              onPressed: widget.currentEpisodeIndex > 0
                                  ? () => _openEpisode(widget.currentEpisodeIndex - 1)
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
                              onPressed: widget.currentEpisodeIndex < widget.episodes.length - 1
                                  ? () => _openEpisode(widget.currentEpisodeIndex + 1)
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
        NativeVideoPlayer(controller: c),
        if (_showQos) _buildQosPanel(app),
      ],
    );
  }

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

  void _startHistoryTracking() {
    _historyTimer?.cancel();
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistHistoryPosition();
    });
  }

  void _persistHistoryPosition() {
    final c = _controller;
    if (c == null) return;
    final seconds = c.currentPosition.inSeconds;
    if (seconds < 0 || seconds == _lastSavedPosition) return;
    _lastSavedPosition = seconds;
    unawaited(
      AppScope.read(context).addHistory(widget.item, positionSeconds: seconds),
    );
  }

  Widget _buildQosPanel(AppController app) {
    final c = _controller;
    return Positioned(
      left: 10,
      top: 10,
      child: Container(
        width: 220,
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
              const Text('QoS Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
              const Text('引擎: Native (better_native_video_player)'),
              Text('本次启动: ${_sessionStartupMs}ms'),
              Text('累计会话: ${app.qosSessionCount}'),
              Text('平均启动: ${app.qosAvgStartupMs}ms'),
              Text('缓冲次数: ${app.qosBufferEvents}'),
              Text('缓冲总时长: ${app.qosBufferTotalMs}ms'),
              Text('重试次数: ${app.qosRetryCount}'),
              Text('错误次数: ${app.qosErrorCount}'),
              if (c != null) Text('状态: ${c.activityState.name}'),
              if (c != null) Text('位置: ${c.currentPosition.inSeconds}s / ${c.duration.inSeconds}s'),
            ],
          ),
        ),
      ),
    );
  }

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
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        result.add(parsed);
      }

      final encodedValue = Uri.encodeFull(value);
      if (!unique.contains(encodedValue)) {
        unique.add(encodedValue);
        final encodedParsed = Uri.tryParse(encodedValue);
        if (encodedParsed != null &&
            encodedParsed.hasScheme &&
            encodedParsed.host.isNotEmpty) {
          result.add(encodedParsed);
        }
      }
    }

    return result;
  }

  String _resolvePlaybackUrl(String rawUrl, AppSettings settings) {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty) return normalized;

    if (!_isHlsUrl(normalized)) return normalized;
    if (!settings.hlsAdFilterEnabled) return normalized;

    final proxyBase = settings.hlsProxyBaseUrl.trim().isNotEmpty
        ? settings.hlsProxyBaseUrl.trim()
        : settings.proxyBaseUrl.trim();
    if (proxyBase.isEmpty) return normalized;

    final baseUri = Uri.tryParse(proxyBase);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      return normalized;
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

  Map<String, String> _buildPlaybackHeaders(Uri uri) {
    final origin = uri.hasScheme && uri.host.isNotEmpty ? '${uri.scheme}://${uri.host}' : '';
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

    final targetIndex = widget.currentEpisodeIndex >= 0 ? widget.currentEpisodeIndex : 0;
    final output = <String>[];

    final sources = raw.split(r'$$$');
    for (final source in sources) {
      final s = source.trim();
      if (s.isEmpty) continue;
      final delimiter = s.contains('#') ? '#' : '|';
      final entries = s.split(delimiter).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (entries.isEmpty) continue;

      final episodeEntry = targetIndex < entries.length ? entries[targetIndex] : entries.first;
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
    var url = splitAt == -1
        ? normalized
        : normalized.substring(splitAt + 1).trim();

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
