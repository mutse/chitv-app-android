import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../app/app_theme.dart';
import '../../core/models/ad_filter.dart';
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
    this.initialPositionSeconds = 0,
  });

  final VideoItem item;
  final List<EpisodeItem> episodes;
  final int currentEpisodeIndex;
  final String? seriesTitle;
  final int initialPositionSeconds;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  BetterPlayerController? _controller;
  bool _loading = true;
  String? _error;
  String? _subtitleStatus;
  bool _endHandled = false;
  bool _isFullScreen = false;
  int _retry = 0;
  bool _showQos = false;
  int _sessionStartupMs = 0;
  Timer? _historyTimer;
  int _lastSavedPosition = -1;
  final Map<String, String> _localFilteredManifestCache = <String, String>{};
  bool _resumeApplied = false;
  String? _activeSubtitleUrl;

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
    _restoreSystemUi();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _initialize(String url) async {
    final startedAt = DateTime.now();
    final app = AppScope.read(context);
    final settings = app.settings;
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
      await _loadDefaultSubtitleIfNeeded(playerController, app);
      await _resumePlaybackIfNeeded(playerController);
      if (!mounted) return;

      _sessionStartupMs = DateTime.now().difference(startedAt).inMilliseconds;
      app.recordPlaybackSessionStarted(startupMs: _sessionStartupMs);
      setState(() => _loading = false);

      _startHistoryTracking();
      unawaited(app.addHistory(widget.item));
    } catch (e) {
      if (!mounted) return;

      if (_retry < 2) {
        _retry += 1;
        AppScope.read(context).recordPlaybackRetry();
        await Future<void>.delayed(Duration(milliseconds: 400 * _retry));
        return _initialize(url);
      }

      AppScope.read(context).recordPlaybackError();
      final msg = e is TimeoutException ? '播放超时，请检查网络或代理配置后重试' : '播放失败: $e';
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
    final settings = AppScope.read(context).settings;

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
        enableSubtitles: true,
        overflowMenuCustomItems: const [],
        loadingWidget: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
      subtitlesConfiguration: const BetterPlayerSubtitlesConfiguration(
        fontSize: 16,
        backgroundColor: Colors.black54,
        leftPadding: 20,
        rightPadding: 20,
        bottomPadding: 26,
      ),
      // Error widget — mirrors the "⚠️ 视频加载失败" from player.html.
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                '视频加载失败',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
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
    final headers = isLocalFile
        ? const <String, String>{}
        : _buildPlaybackHeaders(uri);
    final dataSource = BetterPlayerDataSource(
      isLocalFile
          ? BetterPlayerDataSourceType.file
          : BetterPlayerDataSourceType.network,
      isLocalFile ? uri.toFilePath() : uri.toString(),
      videoFormat: isHls
          ? BetterPlayerVideoFormat.hls
          : BetterPlayerVideoFormat.other,
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
      subtitles: _buildInitialSubtitleSources(settings),
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

        case BetterPlayerEventType.openFullscreen:
          _handleFullScreenChanged(true);
          break;

        case BetterPlayerEventType.hideFullscreen:
          _handleFullScreenChanged(false);
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
    if (widget.currentEpisodeIndex < 0 || nextIndex >= widget.episodes.length) {
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

  Future<void> _resumePlaybackIfNeeded(BetterPlayerController controller) async {
    if (_resumeApplied || widget.initialPositionSeconds <= 0) return;
    _resumeApplied = true;

    final target = Duration(seconds: widget.initialPositionSeconds);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.seekTo(target);
      _lastSavedPosition = widget.initialPositionSeconds;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从 ${widget.initialPositionSeconds}s 处继续播放')),
      );
    } catch (_) {
      // Ignore seek failures so playback can continue from the start.
    }
  }

  List<BetterPlayerSubtitlesSource>? _buildInitialSubtitleSources(
    AppSettings settings,
  ) {
    if (!settings.subtitleEnabled) return null;
    final subtitleUrl = settings.defaultSubtitleUrl.trim();
    if (subtitleUrl.isEmpty) return null;
    return BetterPlayerSubtitlesSource.single(
      type: BetterPlayerSubtitlesSourceType.network,
      name: '默认字幕',
      url: subtitleUrl,
      selectedByDefault: true,
      headers: _buildSubtitleHeaders(subtitleUrl),
    );
  }

  Map<String, String> _buildSubtitleHeaders(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return const <String, String>{};
    }
    return _buildPlaybackHeaders(parsed);
  }

  Future<void> _loadDefaultSubtitleIfNeeded(
    BetterPlayerController controller,
    AppController app,
  ) async {
    final url = app.settings.defaultSubtitleUrl.trim();
    if (!app.settings.subtitleEnabled || url.isEmpty) return;
    await _applySubtitleUrl(
      url,
      controller: controller,
      app: app,
      rememberOnly: true,
      statusText: '已加载默认字幕',
    );
  }

  Future<void> _applySubtitleUrl(
    String url, {
    BetterPlayerController? controller,
    AppController? app,
    bool rememberOnly = false,
    String? statusText,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final currentController = controller ?? _controller;
    final currentApp = app ?? AppScope.read(context);
    if (currentController == null) return;

    final source = BetterPlayerSubtitlesSource(
      type: BetterPlayerSubtitlesSourceType.network,
      name: '外部字幕',
      urls: [trimmed],
      headers: _buildSubtitleHeaders(trimmed),
    );

    try {
      await currentController.setupSubtitleSource(source);
      await currentApp.rememberSubtitleUrl(trimmed, makeDefault: !rememberOnly);
      if (!mounted) return;
      setState(() {
        _activeSubtitleUrl = trimmed;
        _subtitleStatus = statusText ?? '已加载字幕';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _subtitleStatus = '字幕加载失败: $e');
    }
  }

  Future<void> _disableSubtitles() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setupSubtitleSource(
        BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none),
      );
      if (!mounted) return;
      setState(() {
        _activeSubtitleUrl = null;
        _subtitleStatus = '字幕已关闭';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _subtitleStatus = '关闭字幕失败: $e');
    }
  }

  Future<void> _showSubtitleSheet() async {
    final app = AppScope.read(context);
    final subtitleController = TextEditingController(
      text: _activeSubtitleUrl ?? app.settings.defaultSubtitleUrl,
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '字幕选项',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subtitleController,
                  decoration: const InputDecoration(
                    labelText: '字幕 URL (.srt/.vtt)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _applySubtitleUrl(
                            subtitleController.text,
                            rememberOnly: true,
                            statusText: '已加载外部字幕',
                          );
                        },
                        child: const Text('仅本次加载'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _applySubtitleUrl(
                            subtitleController.text,
                            rememberOnly: false,
                            statusText: '已加载并设为默认字幕',
                          );
                        },
                        child: const Text('设为默认'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _disableSubtitles();
                    },
                    icon: const Icon(Icons.closed_caption_disabled_outlined),
                    label: const Text('关闭字幕'),
                  ),
                ),
                if (app.settings.recentSubtitleUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '最近使用',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: app.settings.recentSubtitleUrls.map((url) {
                      return ActionChip(
                        label: SizedBox(
                          width: 220,
                          child: Text(url, overflow: TextOverflow.ellipsis),
                        ),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await _applySubtitleUrl(
                            url,
                            rememberOnly: true,
                            statusText: '已加载最近使用的字幕',
                          );
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    subtitleController.dispose();
  }

  Future<void> _showPlaybackPreferencesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final app = AppScope.of(context);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '播放偏好',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: app.settings.autoPlayNext,
                      onChanged: (value) async {
                        await app.setAutoPlayNext(value);
                        if (mounted) {
                          setSheetState(() {});
                          setState(() {});
                        }
                      },
                      title: const Text('自动播放下一集'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: app.settings.loopPlayback,
                      onChanged: (value) async {
                        await app.setLoopPlayback(value);
                        final controller = _controller;
                        if (controller != null) {
                          controller.setLooping(value);
                        }
                        if (mounted) {
                          setSheetState(() {});
                          setState(() {});
                        }
                      },
                      title: const Text('单集循环播放'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: app.settings.subtitleEnabled,
                      onChanged: (value) async {
                        await app.setSubtitleEnabled(value);
                        if (!value) {
                          await _disableSubtitles();
                        } else if (app.settings.defaultSubtitleUrl.trim().isNotEmpty) {
                          await _applySubtitleUrl(
                            app.settings.defaultSubtitleUrl,
                            rememberOnly: true,
                            statusText: '已重新启用默认字幕',
                          );
                        }
                        if (mounted) {
                          setSheetState(() {});
                          setState(() {});
                        }
                      },
                      title: const Text('启用字幕'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _showSubtitleSheet();
                        },
                        icon: const Icon(Icons.closed_caption_outlined),
                        label: const Text('打开字幕面板'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
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
        title: ChiTvNavTitle(
          eyebrow: widget.seriesTitle?.isNotEmpty == true ? 'Now Playing' : 'Player',
          title: widget.seriesTitle?.isNotEmpty == true
              ? widget.seriesTitle!
              : widget.item.title,
        ),
        actions: [
                  // Engine badge
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Center(
                        child: Text(
                          _activeSubtitleUrl == null ? '字幕已启用' : '字幕已加载',
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: _showSubtitleSheet,
                    icon: const Icon(Icons.closed_caption_outlined),
                    tooltip: '字幕',
                  ),
                  IconButton(
                    onPressed: _showPlaybackPreferencesSheet,
                    icon: const Icon(Icons.tune_rounded),
                    tooltip: '播放偏好',
                  ),
                  IconButton(
                    onPressed: _toggleFullScreen,
                    icon: Icon(
                      _isFullScreen
                          ? Icons.fullscreen_exit_outlined
                          : Icons.fullscreen_outlined,
                    ),
                    tooltip: _isFullScreen ? '退出全屏' : '全屏播放',
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
                  if (_subtitleStatus != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.subtitles_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_subtitleStatus!)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PlayerStatusChip(
                          icon: Icons.skip_next_rounded,
                          label: app.settings.autoPlayNext ? '自动下一集: 开' : '自动下一集: 关',
                        ),
                        _PlayerStatusChip(
                          icon: Icons.repeat_rounded,
                          label: app.settings.loopPlayback ? '循环播放: 开' : '循环播放: 关',
                        ),
                        _PlayerStatusChip(
                          icon: Icons.closed_caption_outlined,
                          label: _activeSubtitleUrl == null
                              ? (app.settings.subtitleEnabled ? '字幕: 待加载' : '字幕: 关')
                              : '字幕: 已加载',
                        ),
                      ],
                    ),
                  ),
                  // Player area
                  Expanded(child: Center(child: _buildPlayer(app))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _seekBySeconds(-10),
                            icon: const Icon(Icons.replay_10_rounded, size: 18),
                            label: const Text('快退 10 秒'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _seekBySeconds(10),
                            icon: const Icon(Icons.forward_10_rounded, size: 18),
                            label: const Text('快进 10 秒'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Episode navigation (prev / next)
                  if (widget.currentEpisodeIndex >= 0 && widget.episodes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: widget.currentEpisodeIndex > 0
                                ? () => _openEpisode(
                                    widget.currentEpisodeIndex - 1,
                                  )
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
                            onPressed:
                                widget.currentEpisodeIndex <
                                    widget.episodes.length - 1
                                ? () => _openEpisode(
                                    widget.currentEpisodeIndex + 1,
                                  )
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

  Future<void> _toggleFullScreen() async {
    final controller = _controller;
    if (controller == null) return;
    controller.toggleFullScreen();
  }

  void _handleFullScreenChanged(bool isFullScreen) {
    if (!mounted || _isFullScreen == isFullScreen) return;

    if (!isFullScreen) {
      _restoreSystemUi();
    }

    setState(() {
      _isFullScreen = isFullScreen;
    });
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
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

  Future<void> _seekBySeconds(int seconds) async {
    final controller = _controller;
    final vp = controller?.videoPlayerController;
    if (controller == null || vp == null || !vp.value.initialized) return;

    final duration = vp.value.duration ?? Duration.zero;
    final position = vp.value.position;
    final target = Duration(
      milliseconds: position.inMilliseconds + seconds * 1000,
    );
    final bounded = Duration(
      milliseconds: target.inMilliseconds.clamp(
        0,
        duration.inMilliseconds > 0 ? duration.inMilliseconds : target.inMilliseconds,
      ),
    );

    controller.seekTo(bounded);
    if (!mounted) return;
    setState(() {
      _subtitleStatus = '${seconds > 0 ? '已快进' : '已快退'} ${seconds.abs()} 秒';
    });
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
          initialPositionSeconds: 0,
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
              const Text(
                'QoS Monitor',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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
  Future<String> _resolvePlaybackUrl(
    String rawUrl,
    AppSettings settings,
  ) async {
    final normalized = rawUrl.trim();
    if (normalized.isEmpty) return normalized;

    if (!_isHlsUrl(normalized)) return normalized;
    if (!settings.hlsAdFilterEnabled) return normalized;

    final proxyBase = settings.hlsProxyBaseUrl.trim().isNotEmpty
        ? settings.hlsProxyBaseUrl.trim()
        : settings.proxyBaseUrl.trim();
    if (proxyBase.isEmpty) {
      return _buildLocalFilteredManifest(normalized, settings: settings);
    }

    final baseUri = Uri.tryParse(proxyBase);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      return _buildLocalFilteredManifest(normalized, settings: settings);
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

  Future<String> _buildLocalFilteredManifest(
    String sourceUrl, {
    required AppSettings settings,
  }) async {
    if (_localFilteredManifestCache.containsKey(sourceUrl)) {
      return _localFilteredManifestCache[sourceUrl]!;
    }

    final sourceUri = Uri.tryParse(sourceUrl);
    if (sourceUri == null || !sourceUri.hasScheme || sourceUri.host.isEmpty) {
      return sourceUrl;
    }

    try {
      final response = await http
          .get(sourceUri, headers: _buildPlaybackHeaders(sourceUri))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return sourceUrl;

      final body = response.body;
      if (!body.trimLeft().startsWith('#EXTM3U')) return sourceUrl;

      final filtered = _filterAdsFromM3u8(body, sourceUri, settings: settings);
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

  String _filterAdsFromM3u8(
    String content,
    Uri sourceUri, {
    required AppSettings settings,
  }) {
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

      final resolved = base.resolve(line).toString();
      if (_matchesAdFilter(resolved, settings.adFilters)) {
        if (output.isNotEmpty && output.last.trim().startsWith('#EXTINF')) {
          output.removeLast();
        }
        continue;
      }

      output.add(resolved);
    }

    return output.join('\n');
  }

  bool _matchesAdFilter(String value, List<AdFilter> filters) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    for (final filter in filters) {
      if (!filter.enabled) continue;
      final pattern = filter.pattern.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      if (normalized.contains(pattern)) return true;
    }

    return false;
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

    final targetIndex = widget.currentEpisodeIndex >= 0
        ? widget.currentEpisodeIndex
        : 0;
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

      final episodeEntry = targetIndex < entries.length
          ? entries[targetIndex]
          : entries.first;
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

class _PlayerStatusChip extends StatelessWidget {
  const _PlayerStatusChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
