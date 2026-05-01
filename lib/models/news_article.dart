class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.url,
    required this.summary,
    required this.publishedAt,
    required this.fetchedAt,
    this.locationLabel,
    this.content,
    this.contentFetchedAt,
    this.contentStatus,
  });

  final String id;
  final String title;
  final String source;
  final String url;
  final String summary;
  final DateTime publishedAt;
  final DateTime fetchedAt;
  final String? locationLabel;
  final String? content;
  final DateTime? contentFetchedAt;
  final String? contentStatus;

  NewsArticle copyWith({
    String? id,
    String? title,
    String? source,
    String? url,
    String? summary,
    DateTime? publishedAt,
    DateTime? fetchedAt,
    String? locationLabel,
    String? content,
    DateTime? contentFetchedAt,
    String? contentStatus,
  }) {
    return NewsArticle(
      id: id ?? this.id,
      title: title ?? this.title,
      source: source ?? this.source,
      url: url ?? this.url,
      summary: summary ?? this.summary,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      locationLabel: locationLabel ?? this.locationLabel,
      content: content ?? this.content,
      contentFetchedAt: contentFetchedAt ?? this.contentFetchedAt,
      contentStatus: contentStatus ?? this.contentStatus,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'source': source,
    'url': url,
    'summary': summary,
    'publishedAt': publishedAt.toIso8601String(),
    'fetchedAt': fetchedAt.toIso8601String(),
    'locationLabel': locationLabel,
    'content': content,
    'contentFetchedAt': contentFetchedAt?.toIso8601String(),
    'contentStatus': contentStatus,
  };

  factory NewsArticle.fromJson(Map<dynamic, dynamic> json) => NewsArticle(
    id: json['id'] as String,
    title: json['title'] as String,
    source: json['source'] as String,
    url: json['url'] as String,
    summary: json['summary'] as String,
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    locationLabel: json['locationLabel'] as String?,
    content: json['content'] as String?,
    contentFetchedAt: json['contentFetchedAt'] == null
        ? null
        : DateTime.tryParse(json['contentFetchedAt'] as String),
    contentStatus: json['contentStatus'] as String?,
  );
}
