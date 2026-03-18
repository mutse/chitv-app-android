class AdFilter {
  const AdFilter({
    required this.id,
    required this.pattern,
    required this.type,
    this.enabled = true,
  });

  static const List<AdFilter> defaultFilters = [
    AdFilter(
      id: 'default_doubleclick',
      pattern: 'doubleclick',
      type: AdFilterType.domain,
    ),
    AdFilter(
      id: 'default_googlesyndication',
      pattern: 'googlesyndication',
      type: AdFilterType.domain,
    ),
    AdFilter(
      id: 'default_adservice',
      pattern: 'adservice',
      type: AdFilterType.domain,
    ),
    AdFilter(
      id: 'default_ad_dash',
      pattern: 'ad-',
      type: AdFilterType.urlPattern,
    ),
  ];

  final String id;
  final String pattern;
  final AdFilterType type;
  final bool enabled;

  AdFilter copyWith({
    String? id,
    String? pattern,
    AdFilterType? type,
    bool? enabled,
  }) {
    return AdFilter(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pattern': pattern,
        'type': type.name,
        'enabled': enabled,
      };

  factory AdFilter.fromJson(Map<String, dynamic> json) {
    return AdFilter(
      id: json['id'] as String? ?? '',
      pattern: json['pattern'] as String? ?? '',
      type: AdFilterType.fromValue(json['type'] as String?),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

enum AdFilterType {
  domain('域名'),
  urlPattern('URL 规则'),
  keyword('关键字');

  const AdFilterType(this.label);

  final String label;

  static AdFilterType fromValue(String? value) {
    return switch (value) {
      'domain' => AdFilterType.domain,
      'keyword' => AdFilterType.keyword,
      _ => AdFilterType.urlPattern,
    };
  }
}
