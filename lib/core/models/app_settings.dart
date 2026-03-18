class AppSettings {
  const AppSettings({
    this.adultFilterEnabled = true,
    this.autoPlayNext = false,
    this.subtitleEnabled = false,
    this.defaultSubtitleUrl = '',
    this.recentSubtitleUrls = const [],
    this.hlsProxyBaseUrl = '',
    this.hlsAdFilterEnabled = true,
    this.proxyBaseUrl = '',
  });

  final bool adultFilterEnabled;
  final bool autoPlayNext;
  final bool subtitleEnabled;
  final String defaultSubtitleUrl;
  final List<String> recentSubtitleUrls;
  final String hlsProxyBaseUrl;
  final bool hlsAdFilterEnabled;
  final String proxyBaseUrl;

  AppSettings copyWith({
    bool? adultFilterEnabled,
    bool? autoPlayNext,
    bool? subtitleEnabled,
    String? defaultSubtitleUrl,
    List<String>? recentSubtitleUrls,
    String? hlsProxyBaseUrl,
    bool? hlsAdFilterEnabled,
    String? proxyBaseUrl,
  }) {
    return AppSettings(
      adultFilterEnabled: adultFilterEnabled ?? this.adultFilterEnabled,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
      defaultSubtitleUrl: defaultSubtitleUrl ?? this.defaultSubtitleUrl,
      recentSubtitleUrls: recentSubtitleUrls ?? this.recentSubtitleUrls,
      hlsProxyBaseUrl: hlsProxyBaseUrl ?? this.hlsProxyBaseUrl,
      hlsAdFilterEnabled: hlsAdFilterEnabled ?? this.hlsAdFilterEnabled,
      proxyBaseUrl: proxyBaseUrl ?? this.proxyBaseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'adultFilterEnabled': adultFilterEnabled,
    'autoPlayNext': autoPlayNext,
    'subtitleEnabled': subtitleEnabled,
    'defaultSubtitleUrl': defaultSubtitleUrl,
    'recentSubtitleUrls': recentSubtitleUrls,
    'hlsProxyBaseUrl': hlsProxyBaseUrl,
    'hlsAdFilterEnabled': hlsAdFilterEnabled,
    'proxyBaseUrl': proxyBaseUrl,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      adultFilterEnabled: json['adultFilterEnabled'] as bool? ?? true,
      autoPlayNext: json['autoPlayNext'] as bool? ?? false,
      subtitleEnabled: json['subtitleEnabled'] as bool? ?? false,
      defaultSubtitleUrl: json['defaultSubtitleUrl'] as String? ?? '',
      recentSubtitleUrls: (json['recentSubtitleUrls'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      hlsProxyBaseUrl: json['hlsProxyBaseUrl'] as String? ?? '',
      hlsAdFilterEnabled: json['hlsAdFilterEnabled'] as bool? ?? true,
      proxyBaseUrl: json['proxyBaseUrl'] as String? ?? '',
    );
  }
}
