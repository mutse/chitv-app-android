import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A WebView-based HLS player that uses HLS.js for playback --
/// the same approach used by LibreTV.
///
/// This handles HLS streams that the native ExoPlayer-based video_player
/// cannot play due to MediaCodec renderer errors on certain MPEG-TS segments.
class HlsWebViewPlayer extends StatefulWidget {
  const HlsWebViewPlayer({
    super.key,
    required this.url,
    this.title = '',
    this.autoPlay = true,
    this.onEnded,
    this.onError,
    this.onPlaying,
    this.headers = const {},
  });

  final String url;
  final String title;
  final bool autoPlay;
  final VoidCallback? onEnded;
  final ValueChanged<String>? onError;
  final VoidCallback? onPlaying;
  final Map<String, String> headers;

  @override
  State<HlsWebViewPlayer> createState() => HlsWebViewPlayerState();
}

class HlsWebViewPlayerState extends State<HlsWebViewPlayer> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _ready = true);
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onJsMessage,
      )
      ..setBackgroundColor(Colors.black)
      ..loadHtmlString(_buildHtml(widget.url), baseUrl: 'about:blank');
  }

  void _onJsMessage(JavaScriptMessage message) {
    final body = message.message;
    if (body == 'ended') {
      widget.onEnded?.call();
    } else if (body == 'playing') {
      widget.onPlaying?.call();
    } else if (body.startsWith('error:')) {
      widget.onError?.call(body.substring(6));
    }
  }

  /// Load a new URL without recreating the WebView.
  void loadUrl(String url) {
    final escaped = url.replaceAll("'", "\\'").replaceAll('\\', '\\\\');
    _controller.runJavaScript("loadNewSource('$escaped');");
  }

  /// Pause playback.
  void pause() {
    _controller.runJavaScript('pausePlayer();');
  }

  /// Resume playback.
  void play() {
    _controller.runJavaScript('resumePlayer();');
  }

  /// Get current playback position in seconds (async).
  Future<double> get currentPosition async {
    final result = await _controller.runJavaScriptReturningResult(
      'getCurrentPosition();',
    );
    return double.tryParse('$result') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_ready)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
      ],
    );
  }

  /// Build a self-contained HTML page with HLS.js player --
  /// referencing LibreTV's player implementation for HLS config & error handling.
  String _buildHtml(String videoUrl) {
    final escapedUrl = const HtmlEscape().convert(videoUrl);
    final escapedTitle = const HtmlEscape().convert(widget.title);

    return '''
<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>$escapedTitle</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body {
      width: 100%; height: 100%;
      background: #000;
      overflow: hidden;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: #000;
    }
    .loading-overlay {
      position: absolute;
      inset: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      background: rgba(0,0,0,0.7);
      z-index: 10;
    }
    .spinner {
      width: 40px; height: 40px;
      border: 3px solid rgba(255,255,255,0.3);
      border-top-color: #fff;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .error-panel {
      position: absolute;
      inset: 0;
      display: none;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: rgba(0,0,0,0.85);
      color: #fff;
      font-size: 14px;
      z-index: 20;
      padding: 20px;
      text-align: center;
    }
    .error-panel.visible { display: flex; }
  </style>
</head>
<body>
  <div id="container" style="position:relative;width:100%;height:100%;">
    <video id="video" playsinline webkit-playsinline controls></video>
    <div class="loading-overlay" id="loadingOverlay">
      <div class="spinner"></div>
    </div>
    <div class="error-panel" id="errorPanel">
      <div id="errorMsg">视频加载失败</div>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
  <script>
    var currentHls = null;
    var video = document.getElementById('video');
    var loadingOverlay = document.getElementById('loadingOverlay');
    var errorPanel = document.getElementById('errorPanel');
    var errorMsg = document.getElementById('errorMsg');

    function notify(msg) {
      try { FlutterBridge.postMessage(msg); } catch(e) {}
    }

    function hideLoading() { loadingOverlay.style.display = 'none'; }
    function showLoading() { loadingOverlay.style.display = 'flex'; }
    function showError(msg) {
      hideLoading();
      errorMsg.textContent = msg;
      errorPanel.classList.add('visible');
      notify('error:' + msg);
    }

    function loadNewSource(url) {
      errorPanel.classList.remove('visible');
      showLoading();
      initPlayer(url);
    }

    function pausePlayer() { video.pause(); }
    function resumePlayer() { video.play().catch(function(){}); }
    function getCurrentPosition() { return video.currentTime || 0; }

    function initPlayer(url) {
      // Destroy previous instance
      if (currentHls && currentHls.destroy) {
        try { currentHls.destroy(); } catch(e) {}
        currentHls = null;
      }

      if (!url) { showError('无效的视频链接'); return; }

      if (Hls.isSupported()) {
        // HLS.js config -- referencing LibreTV's hlsConfig
        var hlsConfig = {
          debug: false,
          enableWorker: true,
          lowLatencyMode: false,
          backBufferLength: 90,
          maxBufferLength: 30,
          maxMaxBufferLength: 60,
          maxBufferSize: 30 * 1000 * 1000,
          maxBufferHole: 0.5,
          fragLoadingMaxRetry: 6,
          fragLoadingMaxRetryTimeout: 64000,
          fragLoadingRetryDelay: 1000,
          manifestLoadingMaxRetry: 3,
          manifestLoadingRetryDelay: 1000,
          levelLoadingMaxRetry: 4,
          levelLoadingRetryDelay: 1000,
          startLevel: -1,
          abrEwmaDefaultEstimate: 500000,
          abrBandWidthFactor: 0.95,
          abrBandWidthUpFactor: 0.7,
          abrMaxWithRealBitrate: true,
          stretchShortVideoTrack: true,
          appendErrorMaxRetry: 5,
          liveSyncDurationCount: 3,
          liveDurationInfinity: false
        };

        var hls = new Hls(hlsConfig);
        currentHls = hls;

        var errorCount = 0;
        var playbackStarted = false;
        var bufferAppendErrorCount = 0;

        video.addEventListener('playing', function() {
          playbackStarted = true;
          hideLoading();
          errorPanel.classList.remove('visible');
          notify('playing');
        });

        video.addEventListener('timeupdate', function() {
          if (video.currentTime > 1) {
            errorPanel.classList.remove('visible');
          }
        });

        video.addEventListener('ended', function() {
          notify('ended');
        });

        hls.loadSource(url);
        hls.attachMedia(video);

        hls.on(Hls.Events.MANIFEST_PARSED, function() {
          video.play().catch(function(e){});
        });

        hls.on(Hls.Events.ERROR, function(event, data) {
          errorCount++;

          // Handle bufferAppendError (LibreTV pattern)
          if (data.details === 'bufferAppendError') {
            bufferAppendErrorCount++;
            if (playbackStarted) return;
            if (bufferAppendErrorCount >= 3) {
              hls.recoverMediaError();
            }
          }

          if (data.fatal && !playbackStarted) {
            switch(data.type) {
              case Hls.ErrorTypes.NETWORK_ERROR:
                hls.startLoad();
                break;
              case Hls.ErrorTypes.MEDIA_ERROR:
                hls.recoverMediaError();
                break;
              default:
                if (errorCount > 3) {
                  showError('视频加载失败，可能是格式不兼容或源不可用');
                }
                break;
            }
          }
        });

        hls.on(Hls.Events.FRAG_LOADED, function() { hideLoading(); });
        hls.on(Hls.Events.LEVEL_LOADED, function() { hideLoading(); });

      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        // Native HLS support (Safari / iOS)
        video.src = url;
        video.addEventListener('loadedmetadata', function() {
          hideLoading();
          video.play().catch(function(){});
        });
        video.addEventListener('playing', function() {
          hideLoading();
          notify('playing');
        });
        video.addEventListener('ended', function() { notify('ended'); });
        video.addEventListener('error', function() {
          showError('视频播放失败');
        });
      } else {
        // Direct play attempt
        video.src = url;
        video.addEventListener('loadedmetadata', function() {
          hideLoading();
          video.play().catch(function(){});
        });
        video.addEventListener('playing', function() {
          hideLoading();
          notify('playing');
        });
        video.addEventListener('ended', function() { notify('ended'); });
        video.addEventListener('error', function() {
          showError('当前浏览器不支持HLS播放');
        });
      }
    }

    // Auto-start
    initPlayer('$escapedUrl');
  </script>
</body>
</html>
''';
  }
}
