import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;

  bool get isApk => name.toLowerCase().endsWith('.apk');
}

class GithubReleaseInfo {
  const GithubReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<GithubReleaseAsset> assets;

  String get normalizedVersion => normalizeReleaseVersion(tagName);

  GithubReleaseAsset? get preferredApkAsset {
    final apkAssets = assets.where((asset) => asset.isApk).toList();
    if (apkAssets.isEmpty) return null;
    apkAssets.sort(
      (a, b) => _scoreAssetName(b.name).compareTo(_scoreAssetName(a.name)),
    );
    return apkAssets.first;
  }

  static int _scoreAssetName(String name) {
    final lower = name.toLowerCase();
    var score = 0;
    if (lower.contains('universal')) score += 100;
    if (lower.contains('release')) score += 50;
    if (lower.contains('arm64')) score += 25;
    if (lower.contains('debug')) score -= 100;
    return score;
  }
}

class GithubReleaseService {
  GithubReleaseService({http.Client? client})
    : _client = client ?? http.Client();

  static const _owner = 'mutse';
  static const _repo = 'chitv-app-android';
  final http.Client _client;

  Future<GithubReleaseInfo> fetchLatestRelease() async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$_owner/$_repo/releases/latest'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'chitv-app-flutter',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('获取最新版本失败（HTTP ${response.statusCode}）');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (asset) => GithubReleaseAsset(
            name: asset['name'] as String? ?? '',
            downloadUrl: asset['browser_download_url'] as String? ?? '',
            size: asset['size'] as int? ?? 0,
          ),
        )
        .where((asset) => asset.downloadUrl.isNotEmpty)
        .toList();

    return GithubReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      assets: assets,
    );
  }

  Future<File> downloadAsset(
    GithubReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final sanitizedName = asset.name.trim().isEmpty
        ? 'chitv-release.apk'
        : asset.name.trim();
    final file = File('${directory.path}/$sanitizedName');

    if (await file.exists()) {
      await file.delete();
    }

    final request = http.Request('GET', Uri.parse(asset.downloadUrl))
      ..headers.addAll(const {
        'Accept': 'application/octet-stream',
        'User-Agent': 'chitv-app-flutter',
      });
    final response = await _client.send(request);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('下载安装包失败（HTTP ${response.statusCode}）');
    }

    final totalBytes = response.contentLength ?? asset.size;
    var receivedBytes = 0;
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(receivedBytes / totalBytes);
        }
      }
    } finally {
      await sink.close();
    }

    onProgress?.call(1);
    return file;
  }
}

String normalizeReleaseVersion(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceFirst(RegExp(r'^[^0-9]*'), '');
}

int compareSemanticVersion(String left, String right) {
  final leftParts = _parseVersionParts(left);
  final rightParts = _parseVersionParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var index = 0; index < maxLength; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }

  return 0;
}

List<int> _parseVersionParts(String input) {
  final normalized = normalizeReleaseVersion(input);
  final core = normalized.split('+').first.split('-').first;
  if (core.isEmpty) return const [0];
  return core.split('.').map((part) {
    final numeric = RegExp(r'\d+').stringMatch(part) ?? '0';
    return int.tryParse(numeric) ?? 0;
  }).toList();
}
