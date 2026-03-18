class DoubanItem {
  const DoubanItem({
    required this.title,
    required this.cover,
    required this.rate,
    required this.url,
  });

  final String title;
  final String cover;
  final double rate;
  final String url;

  factory DoubanItem.fromJson(Map<String, dynamic> json) {
    final rawRate = json['rate'];
    final rate = rawRate is num ? rawRate.toDouble() : double.tryParse('$rawRate') ?? 0;
    return DoubanItem(
      title: '${json['title'] ?? ''}'.trim(),
      cover: '${json['cover'] ?? ''}'.trim(),
      rate: rate,
      url: '${json['url'] ?? ''}'.trim(),
    );
  }
}
