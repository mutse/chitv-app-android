import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
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
  VideoPlayerController? _player;
  bool _loading = true;
  String? _error;
  bool _endHandled = false;
  int _retry = 0;
  bool _showQos = false;
  bool _wasBuffering = false;
  DateTime? _bufferingSince;
  int _sessionStartupMs = 0;

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

    try {
      final old = _player;
      final candidates = _buildUrlCandidates(url);
      if (candidates.isEmpty) {
        throw Exception('无可用播放地址');
      }

      VideoPlayerController? controller;
      Object? lastError;
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

      if (controller == null) {
        throw lastError ?? Exception('播放器初始化失败');
      }

      await old?.dispose();

      controller.addListener(_watchEnded);
      controller.addListener(_watchBuffering);
      await controller.play();

      if (!mounted) return;
      _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
      AppScope.read(context).recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
      setState(() {
        _player = controller;
        _loading = false;
      });

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
        _error = '$e';
      });
    }
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
    _player?.removeListener(_watchEnded);
    _player?.removeListener(_watchBuffering);
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('播放失败: $_error'),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () {
                          _retry = 0;
                          _initialize(widget.item.url);
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: _player!.value.aspectRatio,
                              child: VideoPlayer(_player!),
                            ),
                            if (_showQos) _buildQosPanel(app),
                          ],
                        ),
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
      floatingActionButton: _player == null
          ? null
          : FloatingActionButton(
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
            ),
    );
  }

  void _openEpisode(int index) {
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
              Text('本次启动: ${_sessionStartupMs}ms'),
              Text('累计会话: ${app.qosSessionCount}'),
              Text('平均启动: ${app.qosAvgStartupMs}ms'),
              Text('缓冲次数: ${app.qosBufferEvents}'),
              Text('缓冲总时长: ${app.qosBufferTotalMs}ms'),
              Text('重试次数: ${app.qosRetryCount}'),
              Text('错误次数: ${app.qosErrorCount}'),
              if (value != null) Text('播放中: ${value.isPlaying ? '是' : '否'}'),
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
}
