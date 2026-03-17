import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../core/models/episode_item.dart';
import '../../core/models/video_item.dart';
import 'hls_webview_player.dart';

/// Video playback engine selection.
enum _PlayerEngine {
  /// Native ExoPlayer via `video_player` plugin.
  native,

  /// WebView with HLS.js -- same approach used by LibreTV.
  /// Serves as fallback when native player fails on certain HLS streams
  /// (e.g. MediaCodecVideoRenderer error on video/mp2t).
  hlsWebView,
}

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
  VideoPlayerController? _player;
  bool _loading = true;
  String? _error;
  bool _endHandled = false;
  int _retry = 0;
  bool _showQos = false;
  bool _wasBuffering = false;
  DateTime? _bufferingSince;
  int _sessionStartupMs = 0;
  Timer? _historyTimer;
  int _lastSavedPosition = -1;

  /// Current playback engine.
  _PlayerEngine _engine = _PlayerEngine.native;

  /// Whether we already tried falling back to WebView player.
  bool _triedFallback = false;

  /// Key for the HLS WebView player (used to force rebuild on URL change).
  Key _hlsPlayerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _initialize(widget.item.url);
  }

  Future<void> _initialize(String url) async {
    final startedAt = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
      _endHandled = false;
    });

    // If we already know native player fails for this type, go directly to WebView.
    if (_engine == _PlayerEngine.hlsWebView) {
      _initHlsWebView(url, startedAt);
      return;
    }

    try {
      final old = _player;
      final rawCandidates = _buildRawPlaybackCandidates(url);
      if (rawCandidates.isEmpty) {
        throw Exception('无可用播放地址');
      }

      VideoPlayerController? controller;
      Object? lastError;
      for (final raw in rawCandidates) {
        final candidates = _buildUrlCandidates(raw);
        for (final uri in candidates) {
          VideoPlayerController? next;
          try {
            next = VideoPlayerController.networkUrl(
              uri,
              httpHeaders: _buildPlaybackHeaders(uri),
            );
            await next.initialize();
            controller = next;
            break;
          } catch (e) {
            await next?.dispose();
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

      await old?.dispose();

      controller.addListener(_watchEnded);
      controller.addListener(_watchBuffering);
      controller.addListener(_watchNativeError);
      await controller.play();

      if (!mounted) return;
      _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
      AppScope.read(context).recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
      setState(() {
        _player = controller;
        _loading = false;
      });

      _startHistoryTracking();
      unawaited(AppScope.read(context).addHistory(widget.item));
    } catch (e) {
      if (!mounted) return;

      // Before retry limit, do normal retries.
      if (_retry < 2) {
        _retry += 1;
        AppScope.read(context).recordPlaybackRetry();
        await Future<void>.delayed(Duration(milliseconds: 400 * _retry));
        return _initialize(url);
      }

      // All native retries failed -- fall back to HLS.js WebView player
      // (same approach as LibreTV) if the URL looks like an HLS stream.
      if (!_triedFallback && _isLikelyHlsUrl(url)) {
        _triedFallback = true;
        _fallbackToHlsWebView(url, startedAt);
        return;
      }

      AppScope.read(context).recordPlaybackError();
      setState(() {
        _loading = false;
        _error = '播放失败: $e';
      });
    }
  }

  /// Watch for native player errors after initialization (e.g. MediaCodec
  /// renderer errors that occur mid-playback).
  void _watchNativeError() {
    final c = _player;
    if (c == null) return;
    final v = c.value;
    if (v.hasError && !_triedFallback) {
      final errorDesc = v.errorDescription ?? '';
      // MediaCodecVideoRenderer or similar error -- fall back
      if (errorDesc.contains('MediaCodec') ||
          errorDesc.contains('VideoRenderer') ||
          errorDesc.contains('mp2t')) {
        _triedFallback = true;
        _fallbackToHlsWebView(widget.item.url, DateTime.now());
      }
    }
  }

  /// Switch to HLS.js WebView player (LibreTV approach).
  void _fallbackToHlsWebView(String url, DateTime startedAt) {
    debugPrint('[PlayerScreen] Native player failed, falling back to HLS.js WebView player');
    _player?.removeListener(_watchEnded);
    _player?.removeListener(_watchBuffering);
    _player?.removeListener(_watchNativeError);
    _player?.dispose();
    _player = null;

    setState(() {
      _engine = _PlayerEngine.hlsWebView;
      _loading = false;
      _error = null;
      _hlsPlayerKey = UniqueKey();
    });

    _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
    AppScope.read(context).recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
    _startHistoryTracking();
    unawaited(AppScope.read(context).addHistory(widget.item));
  }

  /// Initialize directly with HLS WebView (skip native player).
  void _initHlsWebView(String url, DateTime startedAt) {
    setState(() {
      _loading = false;
      _error = null;
      _hlsPlayerKey = UniqueKey();
    });

    _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
    AppScope.read(context).recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
    _startHistoryTracking();
    unawaited(AppScope.read(context).addHistory(widget.item));
  }

  bool _isLikelyHlsUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('m3u8') || lower.contains('/hls/');
  }

  void _watchEnded() {
    final c = _player;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized || v.hasError) return;
    if (v.duration.inMilliseconds <= 0) return;

    final remain = v.duration - v.position;
    if (remain.inMilliseconds <= 300 && !_endHandled) {
      _endHandled = true;
      _playNextIfNeeded();
    }
  }

  void _playNextIfNeeded() {
    final app = AppScope.read(context);
    if (!app.settings.autoPlayNext) return;

    final nextIndex = widget.currentEpisodeIndex + 1;
    if (widget.currentEpisodeIndex < 0 || nextIndex >= widget.episodes.length) return;

    _openEpisode(nextIndex);
  }

  void _watchBuffering() {
    final c = _player;
    if (c == null) return;
    final nowBuffering = c.value.isBuffering;
    if (!_wasBuffering && nowBuffering) {
      _bufferingSince = DateTime.now();
      _wasBuffering = true;
    } else if (_wasBuffering && !nowBuffering) {
      final started = _bufferingSince;
      if (started != null) {
        final duration = DateTime.now().difference(started).inMilliseconds;
        if (duration > 0) {
          AppScope.read(context).recordBufferEvent(durationMs: duration);
        }
      }
      _bufferingSince = null;
      _wasBuffering = false;
    }
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _persistHistoryPosition();
    _player?.removeListener(_watchEnded);
    _player?.removeListener(_watchBuffering);
    _player?.removeListener(_watchNativeError);
    _player?.dispose();
    super.dispose();
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
                  color: _engine == _PlayerEngine.hlsWebView
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _engine == _PlayerEngine.hlsWebView ? 'HLS.js' : 'Native',
                  style: TextStyle(
                    fontSize: 10,
                    color: _engine == _PlayerEngine.hlsWebView
                        ? Colors.orange
                        : Colors.green,
                  ),
                ),
              ),
            ),
          ),
          if (_engine == _PlayerEngine.native && _error != null)
            IconButton(
              icon: const Icon(Icons.web),
              tooltip: '切换到WebView播放器',
              onPressed: () {
                _triedFallback = true;
                _retry = 0;
                _fallbackToHlsWebView(widget.item.url, DateTime.now());
              },
            ),
          if (_engine == _PlayerEngine.hlsWebView)
            IconButton(
              icon: const Icon(Icons.videocam),
              tooltip: '切换到原生播放器',
              onPressed: () {
                _player?.dispose();
                _player = null;
                _triedFallback = false;
                _retry = 0;
                setState(() {
                  _engine = _PlayerEngine.native;
                });
                _initialize(widget.item.url);
              },
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
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: () {
                                _retry = 0;
                                _triedFallback = false;
                                setState(() => _engine = _PlayerEngine.native);
                                _initialize(widget.item.url);
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('重试'),
                            ),
                            if (!_triedFallback || _engine != _PlayerEngine.hlsWebView)
                              OutlinedButton.icon(
                                onPressed: () {
                                  _triedFallback = true;
                                  _retry = 0;
                                  _fallbackToHlsWebView(widget.item.url, DateTime.now());
                                },
                                icon: const Icon(Icons.web, size: 16),
                                label: const Text('WebView播放'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: _engine == _PlayerEngine.hlsWebView
                            ? _buildHlsWebViewPlayer()
                            : _buildNativePlayer(app),
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
      floatingActionButton: _engine == _PlayerEngine.native && _player != null
          ? FloatingActionButton(
              onPressed: () {
                final value = _player!.value;
                if (value.isPlaying) {
                  _player!.pause();
                } else {
                  _player!.play();
                }
                setState(() {});
              },
              child: Icon(
                _player!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }

  Widget _buildNativePlayer(AppController app) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: _player!.value.aspectRatio,
          child: VideoPlayer(_player!),
        ),
        if (_showQos) _buildQosPanel(app),
      ],
    );
  }

  Widget _buildHlsWebViewPlayer() {
    final app = AppScope.of(context);
    return Stack(
      children: [
        HlsWebViewPlayer(
          key: _hlsPlayerKey,
          url: widget.item.url,
          title: widget.item.title,
          autoPlay: true,
          onEnded: () {
            if (!_endHandled) {
              _endHandled = true;
              _playNextIfNeeded();
            }
          },
          onPlaying: () {
            debugPrint('[PlayerScreen] HLS.js WebView player started playing');
          },
          onError: (error) {
            debugPrint('[PlayerScreen] HLS.js WebView player error: $error');
            if (mounted) {
              setState(() {
                _error = 'HLS播放失败: $error';
              });
            }
          },
        ),
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
    if (_engine == _PlayerEngine.hlsWebView) {
      // WebView history persist is handled differently (no sync access).
      return;
    }
    final player = _player;
    if (player == null) return;
    final value = player.value;
    if (!value.isInitialized || value.hasError) return;
    final seconds = value.position.inSeconds;
    if (seconds < 0 || seconds == _lastSavedPosition) return;
    _lastSavedPosition = seconds;
    unawaited(
      AppScope.read(context).addHistory(widget.item, positionSeconds: seconds),
    );
  }

  Widget _buildQosPanel(AppController app) {
    final value = _player?.value;
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
              Text('引擎: ${_engine == _PlayerEngine.hlsWebView ? "HLS.js WebView" : "Native ExoPlayer"}'),
              Text('本次启动: ${_sessionStartupMs}ms'),
              Text('累计会话: ${app.qosSessionCount}'),
              Text('平均启动: ${app.qosAvgStartupMs}ms'),
              Text('缓冲次数: ${app.qosBufferEvents}'),
              Text('缓冲总时长: ${app.qosBufferTotalMs}ms'),
              Text('重试次数: ${app.qosRetryCount}'),
              Text('错误次数: ${app.qosErrorCount}'),
              if (value != null) Text('播放中: ${value.isPlaying ? '是' : '否'}'),
              if (_triedFallback) const Text('已回退: 是', style: TextStyle(color: Colors.orange)),
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
