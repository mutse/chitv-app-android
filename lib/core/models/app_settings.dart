class AppSettings {
  static const String defaultDoubanHotEndpoint =
      'https://movie.douban.com/j/search_subjects';

  const AppSettings({
    this.adultFilterEnabled = true,
    this.autoPlayNext = false,
    this.loopPlayback = false,
    this.subtitleEnabled = false,
    this.defaultSubtitleUrl = '',
    this.recentSubtitleUrls = const [],
    this.hlsProxyBaseUrl = '',
    this.hlsAdFilterEnabled = true,
    this.proxyBaseUrl = '',
    this.doubanHotEnabled = true,
    this.doubanHotEndpoint = defaultDoubanHotEndpoint,
    this.appThemeMode = 'system',
  });

  final bool adultFilterEnabled;
  final bool autoPlayNext;
  final bool loopPlayback;
  final bool subtitleEnabled;
  final String defaultSubtitleUrl;
  final List<String> recentSubtitleUrls;
  final String hlsProxyBaseUrl;
  final bool hlsAdFilterEnabled;
  final String proxyBaseUrl;
  final bool doubanHotEnabled;
  final String doubanHotEndpoint;
  final String appThemeMode;

  AppSettings copyWith({
    bool? adultFilterEnabled,
    bool? autoPlayNext,
    bool? loopPlayback,
    bool? subtitleEnabled,
    String? defaultSubtitleUrl,
    List<String>? recentSubtitleUrls,
    String? hlsProxyBaseUrl,
    bool? hlsAdFilterEnabled,
    String? proxyBaseUrl,
    bool? doubanHotEnabled,
    String? doubanHotEndpoint,
    String? appThemeMode,
  }) {
    return AppSettings(
      adultFilterEnabled: adultFilterEnabled ?? this.adultFilterEnabled,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      loopPlayback: loopPlayback ?? this.loopPlayback,
      subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
      defaultSubtitleUrl: defaultSubtitleUrl ?? this.defaultSubtitleUrl,
      recentSubtitleUrls: recentSubtitleUrls ?? this.recentSubtitleUrls,
      hlsProxyBaseUrl: hlsProxyBaseUrl ?? this.hlsProxyBaseUrl,
      hlsAdFilterEnabled: hlsAdFilterEnabled ?? this.hlsAdFilterEnabled,
      proxyBaseUrl: proxyBaseUrl ?? this.proxyBaseUrl,
      doubanHotEnabled: doubanHotEnabled ?? this.doubanHotEnabled,
      doubanHotEndpoint: doubanHotEndpoint ?? this.doubanHotEndpoint,
      appThemeMode: appThemeMode ?? this.appThemeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'adultFilterEnabled': adultFilterEnabled,
    'autoPlayNext': autoPlayNext,
    'loopPlayback': loopPlayback,
    'subtitleEnabled': subtitleEnabled,
    'defaultSubtitleUrl': defaultSubtitleUrl,
    'recentSubtitleUrls': recentSubtitleUrls,
    'hlsProxyBaseUrl': hlsProxyBaseUrl,
    'hlsAdFilterEnabled': hlsAdFilterEnabled,
    'proxyBaseUrl': proxyBaseUrl,
    'doubanHotEnabled': doubanHotEnabled,
    'doubanHotEndpoint': doubanHotEndpoint,
    'appThemeMode': appThemeMode,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      adultFilterEnabled: json['adultFilterEnabled'] as bool? ?? true,
      autoPlayNext: json['autoPlayNext'] as bool? ?? false,
      loopPlayback: json['loopPlayback'] as bool? ?? false,
      subtitleEnabled: json['subtitleEnabled'] as bool? ?? false,
      defaultSubtitleUrl: json['defaultSubtitleUrl'] as String? ?? '',
      recentSubtitleUrls: (json['recentSubtitleUrls'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      hlsProxyBaseUrl: json['hlsProxyBaseUrl'] as String? ?? '',
      hlsAdFilterEnabled: json['hlsAdFilterEnabled'] as bool? ?? true,
      proxyBaseUrl: json['proxyBaseUrl'] as String? ?? '',
      doubanHotEnabled: json['doubanHotEnabled'] as bool? ?? true,
      doubanHotEndpoint:
          json['doubanHotEndpoint'] as String? ?? defaultDoubanHotEndpoint,
      appThemeMode: json['appThemeMode'] as String? ?? 'system',
    );
  }
}
