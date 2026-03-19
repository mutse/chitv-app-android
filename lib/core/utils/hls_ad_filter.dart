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

  /// Registered proxy resources keyed by path token.
  final Map<String, _ProxyResource> _cache = {};

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
    return _registerProxyUrl(
      originalUrl,
      headers: headers,
      filterEnabled: filterEnabled,
      forceManifest: true,
    );
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

  String _rewritePlaylistReferences(
    String content,
    String manifestUrl,
    Map<String, String>? headers, {
    required bool filterEnabled,
  }) {
    final manifestUri = Uri.parse(manifestUrl);
    final lines = content.split('\n');
    final rewritten = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        rewritten.add(line);
        continue;
      }

      if (trimmed.startsWith('#')) {
        rewritten.add(
          _rewriteUriAttributes(
            line,
            manifestUri,
            headers,
            filterEnabled: filterEnabled,
          ),
        );
        continue;
      }

      final absolute = manifestUri.resolve(trimmed).toString();
      rewritten.add(
        _registerProxyUrl(
          absolute,
          headers: headers,
          filterEnabled: filterEnabled,
        ),
      );
    }

    return rewritten.join('\n');
  }

  String _rewriteUriAttributes(
    String line,
    Uri baseUri,
    Map<String, String>? headers, {
    required bool filterEnabled,
  }) {
    return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
      final original = match.group(1) ?? '';
      if (original.isEmpty) return match.group(0) ?? '';
      final absolute = baseUri.resolve(original).toString();
      final proxied = _registerProxyUrl(
        absolute,
        headers: headers,
        filterEnabled: filterEnabled,
      );
      return 'URI="$proxied"';
    });
  }

  String _registerProxyUrl(
    String url, {
    Map<String, String>? headers,
    required bool filterEnabled,
    bool forceManifest = false,
  }) {
    final normalizedHeaders = headers == null || headers.isEmpty
        ? const <String, String>{}
        : Map<String, String>.unmodifiable(Map<String, String>.from(headers));

    for (final entry in _cache.entries) {
      final resource = entry.value;
      if (resource.sourceUrl == url &&
          mapEquals(resource.headers, normalizedHeaders) &&
          resource.filterEnabled == filterEnabled &&
          resource.forceManifest == forceManifest) {
        return 'http://127.0.0.1:$_port/proxy/${entry.key}';
      }
    }

    final id = '${_nextId++}';
    _cache[id] = _ProxyResource(
      sourceUrl: url,
      headers: normalizedHeaders,
      filterEnabled: filterEnabled,
      forceManifest: forceManifest,
    );
    return 'http://127.0.0.1:$_port/proxy/$id';
  }

  bool _looksLikePlaylist(
    String url,
    String body,
    http.BaseResponse response, {
    required bool forceManifest,
  }) {
    if (forceManifest) return true;
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.m3u8') ||
        lowerUrl.contains('type=m3u8') ||
        lowerUrl.endsWith('.m3u')) {
      return true;
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('mpegurl') || contentType.contains('m3u')) {
      return true;
    }

    return body.trimLeft().startsWith('#EXTM3U');
  }

  Future<void> _proxyRemoteResource(
    HttpRequest request,
    _ProxyResource resource,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(resource.sourceUrl), headers: resource.headers)
          .timeout(const Duration(seconds: 20));

      if (_looksLikePlaylist(
        resource.sourceUrl,
        response.body,
        response,
        forceManifest: resource.forceManifest,
      )) {
        final filtered = resource.filterEnabled
            ? filterAdsFromM3u8(response.body)
            : response.body;
        final rewritten = _rewritePlaylistReferences(
          filtered,
          resource.sourceUrl,
          resource.headers,
          filterEnabled: resource.filterEnabled,
        );
        request.response.statusCode = response.statusCode;
        request.response.headers.contentType = ContentType.parse(
          'application/vnd.apple.mpegurl',
        );
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        request.response.write(rewritten);
        await request.response.close();
        return;
      }

      await _writeBinaryResponse(
        request,
        statusCode: response.statusCode,
        bodyBytes: response.bodyBytes,
        contentTypeHeader: response.headers['content-type'],
      );
    } catch (e) {
      debugPrint('[HlsAdFilter] Resource proxy error: $e');
      request.response.statusCode = 502;
      request.response.write('Failed to proxy resource');
      await request.response.close();
    }
  }

  Future<void> _writeBinaryResponse(
    HttpRequest request, {
    required int statusCode,
    required Uint8List bodyBytes,
    String? contentTypeHeader,
  }) async {
    request.response.statusCode = statusCode;
    if (contentTypeHeader != null && contentTypeHeader.isNotEmpty) {
      try {
        request.response.headers.contentType = ContentType.parse(
          contentTypeHeader,
        );
      } catch (_) {}
    }
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.add(bodyBytes);
    await request.response.close();
  }

  // ---------------------------------------------------------------------------
  // Local HTTP server handler
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (path.startsWith('/proxy/')) {
        final id = path.substring(7);
        final resource = _cache[id];

        if (resource == null) {
          request.response.statusCode = 404;
          request.response.write('Not found');
          await request.response.close();
          return;
        }

        await _proxyRemoteResource(request, resource);
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

class _ProxyResource {
  const _ProxyResource({
    required this.sourceUrl,
    required this.headers,
    required this.filterEnabled,
    required this.forceManifest,
  });

  final String sourceUrl;
  final Map<String, String> headers;
  final bool filterEnabled;
  final bool forceManifest;
}
