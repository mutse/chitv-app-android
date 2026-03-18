import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client-side HLS (m3u8) ad filtering, ported from LibreTV's
/// `CustomHlsJsLoader` + `filterAdsFromM3U8()` in `player.js`.
///
/// ## How it works
///
/// LibreTV uses HLS.js's custom loader to intercept m3u8 manifest/level
/// responses and strip `#EXT-X-DISCONTINUITY` tags, which mark boundaries
/// where ad segments are spliced into the HLS stream.
///
/// Since `better_player_plus` uses platform-native HLS decoders (ExoPlayer /
/// AVPlayer) that don't expose a manifest-interceptor API, we implement a
/// **local HTTP proxy** approach:
///
///   1. Fetch the original m3u8 manifest
///   2. Apply the same ad-filtering logic as LibreTV
///   3. Rewrite relative segment URLs to absolute URLs
///   4. Serve the filtered manifest via a local HTTP server
///   5. Feed the local URL to the video player
///
/// This achieves the same result as LibreTV's client-side approach without
/// depending on a server-side proxy for ad-filtering.
class HlsAdFilter {
  HlsAdFilter._();

  static final HlsAdFilter instance = HlsAdFilter._();

  HttpServer? _server;
  int _port = 0;

  /// Cached filtered m3u8 content keyed by path token.
  final Map<String, _FilteredManifest> _cache = {};

  int _nextId = 0;

  /// Start the local proxy server if not already running.
  Future<void> ensureStarted() async {
    if (_server != null) return;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[HlsAdFilter] Local proxy started on port $_port');

    _server!.listen(_handleRequest);
  }

  /// Stop the local server and clear cache.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    _cache.clear();
  }

  /// Process an HLS URL:
  ///   - Fetch the m3u8 manifest
  ///   - Filter out ad segments (strip #EXT-X-DISCONTINUITY)
  ///   - Rewrite relative URLs to absolute
  ///   - Cache and return a local proxy URL
  ///
  /// If the URL is not an m3u8 or filtering is disabled, returns the
  /// original URL unchanged.
  ///
  /// [headers] are forwarded when fetching the original manifest.
  Future<String> processUrl(
    String originalUrl, {
    Map<String, String>? headers,
    bool filterEnabled = true,
  }) async {
    if (!filterEnabled) return originalUrl;

    final lower = originalUrl.toLowerCase();
    if (!lower.contains('.m3u8') &&
        !lower.contains('type=m3u8') &&
        !lower.endsWith('.m3u')) {
      return originalUrl;
    }

    await ensureStarted();

    try {
      final response = await http
          .get(Uri.parse(originalUrl), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
            '[HlsAdFilter] Failed to fetch manifest: ${response.statusCode}');
        return originalUrl;
      }

      final body = response.body;

      // Check if this is a master playlist (contains #EXT-X-STREAM-INF)
      // vs. a media playlist (contains #EXTINF).
      final isMasterPlaylist = body.contains('#EXT-X-STREAM-INF');

      String filtered;
      if (isMasterPlaylist) {
        // For master playlists, rewrite sub-playlist URLs to go through
        // our local proxy so we can filter each quality level too.
        filtered = _rewriteMasterPlaylist(body, originalUrl, headers);
      } else {
        // For media playlists, apply ad filtering.
        filtered = filterAdsFromM3u8(body);
        filtered = _rewriteSegmentUrls(filtered, originalUrl);
      }

      final id = '${_nextId++}';
      _cache[id] = _FilteredManifest(
        content: filtered,
        contentType: 'application/vnd.apple.mpegurl',
      );

      return 'http://127.0.0.1:$_port/m3u8/$id';
    } catch (e) {
      debugPrint('[HlsAdFilter] Error processing m3u8: $e');
      return originalUrl;
    }
  }

  // ---------------------------------------------------------------------------
  // M3U8 ad filtering — ported from LibreTV filterAdsFromM3U8()
  // ---------------------------------------------------------------------------

  /// Filter ad segments from an HLS media playlist.
  ///
  /// This is the direct Dart port of LibreTV's `filterAdsFromM3U8()`:
  ///
  /// ```js
  /// function filterAdsFromM3U8(m3u8Content, strictMode = false) {
  ///     const lines = m3u8Content.split('\n');
  ///     const filteredLines = [];
  ///     for (let i = 0; i < lines.length; i++) {
  ///         const line = lines[i];
  ///         // 只过滤#EXT-X-DISCONTINUITY标识
  ///         if (!line.includes('#EXT-X-DISCONTINUITY')) {
  ///             filteredLines.push(line);
  ///         }
  ///     }
  ///     return filteredLines.join('\n');
  /// }
  /// ```
  ///
  /// `#EXT-X-DISCONTINUITY` marks a break in the timeline where an ad segment
  /// has been spliced in. By stripping these tags, the native HLS decoder
  /// treats the entire stream as continuous, effectively skipping the ad
  /// transition points.
  ///
  /// Additional heuristics beyond what LibreTV does:
  ///   - Remove segments whose URLs contain known ad-server domains
  ///   - Remove very short segments (< 1 s) that often are ad bumpers
  static String filterAdsFromM3u8(String m3u8Content) {
    if (m3u8Content.isEmpty) return '';

    final lines = m3u8Content.split('\n');
    final filtered = <String>[];

    // Track whether we're in a "suspect ad block" — a group of segments
    // surrounded by #EXT-X-DISCONTINUITY tags.
    bool inDiscontinuityBlock = false;
    final pendingBlock = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // ── Core filter: strip #EXT-X-DISCONTINUITY (same as LibreTV) ──
      if (trimmed.startsWith('#EXT-X-DISCONTINUITY')) {
        if (!inDiscontinuityBlock) {
          // Entering a potential ad block.
          inDiscontinuityBlock = true;
          pendingBlock.clear();
        } else {
          // Exiting the block — analyze pending segments.
          // If segments look like ads, discard them. Otherwise, keep.
          if (_isLikelyAdBlock(pendingBlock)) {
            // Discard the ad block.
            pendingBlock.clear();
          } else {
            // Keep the non-ad block.
            filtered.addAll(pendingBlock);
            pendingBlock.clear();
          }
          inDiscontinuityBlock = false;
        }
        continue;
      }

      if (inDiscontinuityBlock) {
        pendingBlock.add(line);
      } else {
        // Normal line — check for per-segment ad indicators.
        if (_isAdSegmentLine(trimmed)) {
          // Skip this segment and its preceding #EXTINF tag.
          if (filtered.isNotEmpty &&
              filtered.last.trim().startsWith('#EXTINF')) {
            filtered.removeLast();
          }
          continue;
        }
        filtered.add(line);
      }
    }

    // If we ended while still in a discontinuity block, flush it.
    if (pendingBlock.isNotEmpty) {
      if (!_isLikelyAdBlock(pendingBlock)) {
        filtered.addAll(pendingBlock);
      }
    }

    return filtered.join('\n');
  }

  /// Known ad-server domain patterns.
  static final _adDomainPatterns = <RegExp>[
    RegExp(r'ad[sv]?\d*\.', caseSensitive: false),
    RegExp(r'doubleclick\.net', caseSensitive: false),
    RegExp(r'googleads', caseSensitive: false),
    RegExp(r'adnxs\.com', caseSensitive: false),
    RegExp(r'adsrvr\.org', caseSensitive: false),
    RegExp(r'advertising\.com', caseSensitive: false),
    RegExp(r'\.ad\.', caseSensitive: false),
    RegExp(r'admaster\.com', caseSensitive: false),
    RegExp(r'cnzz\.com', caseSensitive: false),
    RegExp(r'tanx\.com', caseSensitive: false),
    RegExp(r'miaozhen\.com', caseSensitive: false),
    RegExp(r'mmstat\.com', caseSensitive: false),
  ];

  /// Check if a segment URL line looks like an ad.
  static bool _isAdSegmentLine(String line) {
    if (line.startsWith('#')) return false;
    if (line.isEmpty) return false;

    // Check against known ad domains.
    for (final pattern in _adDomainPatterns) {
      if (pattern.hasMatch(line)) return true;
    }

    return false;
  }

  /// Analyze a block of lines between two #EXT-X-DISCONTINUITY tags
  /// to determine if it's likely an ad block.
  ///
  /// Heuristics:
  ///   1. Very short total duration (< 30 s) → likely ad
  ///   2. Contains ad-domain segment URLs → likely ad
  ///   3. Significantly different segment duration from surrounding content
  static bool _isLikelyAdBlock(List<String> blockLines) {
    if (blockLines.isEmpty) return true;

    double totalDuration = 0;
    int segmentCount = 0;
    bool hasAdDomain = false;

    for (final line in blockLines) {
      final trimmed = line.trim();

      // Parse segment duration from #EXTINF tag.
      if (trimmed.startsWith('#EXTINF:')) {
        final durationStr = trimmed.substring(8).split(',').first;
        final duration = double.tryParse(durationStr) ?? 0;
        totalDuration += duration;
        segmentCount++;
      }

      // Check for ad domains in segment URLs.
      if (!trimmed.startsWith('#') && trimmed.isNotEmpty) {
        if (_isAdSegmentLine(trimmed)) {
          hasAdDomain = true;
        }
      }
    }

    // If any segment URL matches an ad domain, treat as ad.
    if (hasAdDomain) return true;

    // If total duration is very short (< 30 s) with few segments,
    // it's likely a pre-roll/mid-roll ad.
    if (segmentCount > 0 && totalDuration < 30.0 && segmentCount <= 5) {
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // URL rewriting
  // ---------------------------------------------------------------------------

  /// Rewrite relative segment URLs to absolute URLs based on the
  /// original m3u8 manifest URL.
  static String _rewriteSegmentUrls(String content, String manifestUrl) {
    final manifestUri = Uri.parse(manifestUrl);
    final baseUrl = _getBaseUrl(manifestUri);

    final lines = content.split('\n');
    final rewritten = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        rewritten.add(line);
        continue;
      }

      // This is a segment URL — make it absolute if relative.
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        rewritten.add(line);
      } else if (trimmed.startsWith('/')) {
        // Absolute path — prepend scheme + host.
        final absolute =
            '${manifestUri.scheme}://${manifestUri.host}$trimmed';
        rewritten.add(absolute);
      } else {
        // Relative path — resolve against base URL.
        rewritten.add('$baseUrl/$trimmed');
      }
    }

    return rewritten.join('\n');
  }

  /// Rewrite a master playlist so that sub-playlist URLs go through our
  /// local proxy for filtering.
  String _rewriteMasterPlaylist(
    String content,
    String masterUrl,
    Map<String, String>? headers,
  ) {
    final masterUri = Uri.parse(masterUrl);
    final baseUrl = _getBaseUrl(masterUri);

    final lines = content.split('\n');
    final rewritten = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        rewritten.add(lines[i]);
        continue;
      }

      // This is a sub-playlist URL — resolve to absolute.
      String absoluteUrl;
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        absoluteUrl = trimmed;
      } else if (trimmed.startsWith('/')) {
        absoluteUrl =
            '${masterUri.scheme}://${masterUri.host}$trimmed';
      } else {
        absoluteUrl = '$baseUrl/$trimmed';
      }

      // Register a deferred filter entry for this sub-playlist.
      final id = '${_nextId++}';
      _cache[id] = _FilteredManifest(
        content: '', // Will be fetched on demand.
        contentType: 'application/vnd.apple.mpegurl',
        deferredUrl: absoluteUrl,
        deferredHeaders: headers,
      );

      rewritten.add('http://127.0.0.1:$_port/m3u8/$id');
    }

    return rewritten.join('\n');
  }

  static String _getBaseUrl(Uri uri) {
    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) {
      return '${uri.scheme}://${uri.host}';
    }
    final parentSegments = pathSegments.sublist(0, pathSegments.length - 1);
    return '${uri.scheme}://${uri.host}/${parentSegments.join('/')}';
  }

  // ---------------------------------------------------------------------------
  // Local HTTP server handler
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (path.startsWith('/m3u8/')) {
        final id = path.substring(6);
        final manifest = _cache[id];

        if (manifest == null) {
          request.response.statusCode = 404;
          request.response.write('Not found');
          await request.response.close();
          return;
        }

        // If this is a deferred sub-playlist, fetch, filter, and cache it now.
        if (manifest.deferredUrl != null && manifest.content.isEmpty) {
          try {
            final resp = await http
                .get(
                  Uri.parse(manifest.deferredUrl!),
                  headers: manifest.deferredHeaders,
                )
                .timeout(const Duration(seconds: 15));

            if (resp.statusCode == 200) {
              final filtered = filterAdsFromM3u8(resp.body);
              final rewritten =
                  _rewriteSegmentUrls(filtered, manifest.deferredUrl!);
              _cache[id] = _FilteredManifest(
                content: rewritten,
                contentType: manifest.contentType,
              );
            } else {
              request.response.statusCode = resp.statusCode;
              request.response.write(resp.body);
              await request.response.close();
              return;
            }
          } catch (e) {
            debugPrint('[HlsAdFilter] Deferred fetch error: $e');
            request.response.statusCode = 502;
            request.response.write('Failed to fetch sub-playlist');
            await request.response.close();
            return;
          }
        }

        final cached = _cache[id]!;
        request.response.statusCode = 200;
        request.response.headers.contentType =
            ContentType.parse(cached.contentType);
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.write(cached.content);
        await request.response.close();
        return;
      }

      request.response.statusCode = 404;
      request.response.write('Not found');
      await request.response.close();
    } catch (e) {
      debugPrint('[HlsAdFilter] Server error: $e');
      try {
        request.response.statusCode = 500;
        request.response.write('Internal error');
        await request.response.close();
      } catch (_) {}
    }
  }
}

class _FilteredManifest {
  _FilteredManifest({
    required this.content,
    required this.contentType,
    this.deferredUrl,
    this.deferredHeaders,
  });

  String content;
  final String contentType;
  final String? deferredUrl;
  final Map<String, String>? deferredHeaders;
}
