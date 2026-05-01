import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/app_location.dart';
import '../models/news_article.dart';
import 'article_content_service.dart';

class NewsSourceOption {
  const NewsSourceOption({
    required this.name,
    required this.description,
    required this.endpoint,
    required this.enabled,
  });

  final String name;
  final String description;
  final String endpoint;
  final bool enabled;
}

class NewsService {
  static const sourceOptions = [
    NewsSourceOption(
      name: 'GDELT',
      description:
          'Global media monitoring for local headlines, conflict, disaster, and trending reports.',
      endpoint: 'api.gdeltproject.org/api/v2/doc/doc',
      enabled: true,
    ),
    NewsSourceOption(
      name: 'Google News RSS',
      description:
          'No-key search feed for local Iran/Tehran headlines across news publishers.',
      endpoint: 'news.google.com/rss/search',
      enabled: true,
    ),
    NewsSourceOption(
      name: 'ReliefWeb',
      description:
          'UN/OCHA humanitarian reports. Disabled until we register an approved ReliefWeb appname for v2.',
      endpoint: 'api.reliefweb.int/v2/reports',
      enabled: false,
    ),
    NewsSourceOption(
      name: 'GDACS',
      description:
          'Global disaster alerts for earthquakes, floods, cyclones, and other hazards.',
      endpoint: 'gdacs.org/xml/rss.xml',
      enabled: true,
    ),
    NewsSourceOption(
      name: 'X / Social Trends',
      description:
          'Requires an API key or backend aggregator, so it is not enabled in the local-only MVP.',
      endpoint: 'Requires external API/backend',
      enabled: false,
    ),
  ];

  Future<List<NewsArticle>> fetchLocalNews(AppLocation location) async {
    final results = <NewsArticle>[];
    final fetched = await Future.wait([
      _fetchGdelt(location),
      _fetchGoogleNews(location, hazardFocused: false),
      _fetchGoogleNews(location, hazardFocused: true),
      _fetchGdacs(location),
    ]);
    for (final articles in fetched) {
      results.addAll(articles);
    }

    final byId = {for (final article in results) article.id: article};
    final articles = byId.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final trimmed = articles.take(40).toList();
    final topWithContent = await Future.wait(
      trimmed.take(12).map(ArticleContentService().fetchFullContent),
    );
    return [...topWithContent, ...trimmed.skip(topWithContent.length)];
  }

  Future<List<NewsArticle>> _fetchGdelt(AppLocation location) async {
    final placeTerms = [
      location.city,
      location.region,
      location.country,
    ].where((value) => value != null && value.trim().isNotEmpty).join(' OR ');
    final query = placeTerms.isEmpty
        ? 'war OR disaster OR flood OR earthquake OR evacuation'
        : '($placeTerms) (war OR disaster OR flood OR earthquake OR evacuation OR shelter OR explosion OR wildfire OR storm)';

    final uri = Uri.https('api.gdeltproject.org', '/api/v2/doc/doc', {
      'query': query,
      'mode': 'artlist',
      'format': 'json',
      'maxrecords': '30',
      'sort': 'HybridRel',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final articles = decoded['articles'] as List? ?? const [];
      return articles
          .cast<Map<String, dynamic>>()
          .map((json) {
            final url = (json['url'] as String?) ?? '';
            return NewsArticle(
              id: _stableId(url),
              title: (json['title'] as String?) ?? 'Untitled report',
              source: (json['domain'] as String?) ?? 'GDELT',
              url: url,
              summary: (json['seendate'] as String?) ?? 'Local media mention',
              publishedAt: _parseGdeltDate(json['seendate'] as String?),
              fetchedAt: DateTime.now(),
              locationLabel: location.label,
            );
          })
          .where((article) => article.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<NewsArticle>> _fetchGoogleNews(
    AppLocation location, {
    required bool hazardFocused,
  }) async {
    final place = [
      location.city,
      location.country,
    ].where((value) => value != null && value.trim().isNotEmpty).join(' ');
    final query = hazardFocused
        ? '$place earthquake OR war OR explosion OR protest OR evacuation'
        : place;

    final uri = Uri.https('news.google.com', '/rss/search', {
      'q': query,
      'hl': 'en-US',
      'gl': 'US',
      'ceid': 'US:en',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final document = XmlDocument.parse(response.body);
      final items = document.findAllElements('item');
      return items
          .map((item) {
            final title = _xmlText(item, 'title');
            final url = _xmlText(item, 'link');
            final source = _xmlText(item, 'source');
            return NewsArticle(
              id: _stableId(url),
              title: title.isEmpty ? 'Google News report' : title,
              source: source.isEmpty ? 'Google News' : source,
              url: url,
              summary: _stripHtml(_xmlText(item, 'description')),
              publishedAt: _parseHttpDate(_xmlText(item, 'pubDate')),
              fetchedAt: DateTime.now(),
              locationLabel: location.label,
            );
          })
          .where((article) => article.url.isNotEmpty)
          .take(30)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<NewsArticle>> _fetchGdacs(AppLocation location) async {
    final uri = Uri.parse('https://www.gdacs.org/xml/rss.xml');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final document = XmlDocument.parse(response.body);
      final items = document.findAllElements('item');
      final terms = [
        location.city?.toLowerCase(),
        location.country?.toLowerCase(),
      ].whereType<String>().toList();
      return items
          .map((item) {
            final title = _xmlText(item, 'title');
            final description = _stripHtml(_xmlText(item, 'description'));
            final searchable = '$title $description'.toLowerCase();
            if (terms.isNotEmpty &&
                !terms.any((term) => searchable.contains(term))) {
              return null;
            }
            final url = _xmlText(item, 'link');
            return NewsArticle(
              id: _stableId(url),
              title: title.isEmpty ? 'GDACS alert' : title,
              source: 'GDACS',
              url: url,
              summary: description,
              publishedAt: _parseHttpDate(_xmlText(item, 'pubDate')),
              fetchedAt: DateTime.now(),
              locationLabel: location.label,
            );
          })
          .whereType<NewsArticle>()
          .take(20)
          .toList();
    } catch (_) {
      return [];
    }
  }

  DateTime _parseGdeltDate(String? value) {
    if (value == null || value.length < 8) return DateTime.now();
    final normalized = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length < 8) return DateTime.now();
    return DateTime.tryParse(
          '${normalized.substring(0, 4)}-'
          '${normalized.substring(4, 6)}-'
          '${normalized.substring(6, 8)}',
        ) ??
        DateTime.now();
  }

  String _stripHtml(String html) {
    final text = html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length <= 220) return text;
    return '${text.substring(0, 220)}...';
  }

  String _xmlText(XmlElement item, String name) =>
      item.findElements(name).firstOrNull?.innerText.trim() ?? '';

  DateTime _parseHttpDate(String value) {
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }

  String _stableId(String value) => base64Url.encode(utf8.encode(value));
}
