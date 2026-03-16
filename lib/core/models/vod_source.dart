class VodSource {
  const VodSource({
    required this.id,
    required this.name,
    required this.apiUrl,
    this.enabled = true,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String apiUrl;
  final bool enabled;
  final bool isDefault;

  VodSource copyWith({
    String? id,
    String? name,
    String? apiUrl,
    bool? enabled,
    bool? isDefault,
  }) {
    return VodSource(
      id: id ?? this.id,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apiUrl': apiUrl,
    'enabled': enabled,
    'isDefault': isDefault,
  };

  factory VodSource.fromJson(Map<String, dynamic> json) {
    return VodSource(
      id: json['id'] as String,
      name: json['name'] as String,
      apiUrl: json['apiUrl'] as String,
      enabled: json['enabled'] as bool? ?? true,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
