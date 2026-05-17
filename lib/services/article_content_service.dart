import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/news_article.dart';

class ArticleContentService {
  ArticleContentService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<NewsArticle> fetchFullContent(NewsArticle article) async {
    if ((article.content ?? '').trim().length > 300) {
      return article;
    }

    try {
      final sourceUri = await _resolveSourceUri(Uri.parse(article.url));
      final response = await _client
          .get(
            sourceUri,
            headers: const {
              'user-agent':
                  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 HAVEN/1.0',
              'accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 18));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return article.copyWith(
          url: sourceUri.toString(),
          contentStatus: 'Source returned HTTP ${response.statusCode}.',
          contentFetchedAt: DateTime.now(),
        );
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final extracted = _extractReadableText(html);
      if (extracted.length < 300) {
        return article.copyWith(
          url: sourceUri.toString(),
          content: extracted.isEmpty ? null : extracted,
          contentStatus:
              'Could not extract enough readable article text from this source.',
          contentFetchedAt: DateTime.now(),
        );
      }

      return article.copyWith(
        url: sourceUri.toString(),
        content: extracted,
        contentStatus: 'Full text extracted from source page.',
        contentFetchedAt: DateTime.now(),
      );
    } catch (error) {
      return article.copyWith(
        contentStatus: 'Could not fetch full article: $error',
        contentFetchedAt: DateTime.now(),
      );
    }
  }

  Future<Uri> _resolveSourceUri(Uri uri) async {
    if (uri.host != 'news.google.com' ||
        !uri.pathSegments.contains('articles')) {
      return uri;
    }

    try {
      final articleId = uri.pathSegments.last;
      final response = await _client
          .get(uri, headers: const {'user-agent': 'Mozilla/5.0 HAVEN/1.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return uri;

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final document = html_parser.parse(html);
      final dataNode = document.querySelector('c-wiz > div');
      final signature = dataNode?.attributes['data-n-a-sg'];
      final timestamp = dataNode?.attributes['data-n-a-ts'];
      if (signature == null || timestamp == null) return uri;

      final request = jsonEncode([
        'garturlreq',
        [
          [
            'X',
            'X',
            ['X', 'X'],
            null,
            null,
            1,
            1,
            'US:en',
            null,
            1,
            null,
            null,
            null,
            null,
            null,
            0,
            1,
          ],
          'X',
          'X',
          1,
          [1, 1, 1],
          1,
          1,
          null,
          0,
          0,
          null,
          0,
        ],
        articleId,
        int.tryParse(timestamp) ?? timestamp,
        signature,
      ]);
      final payload = jsonEncode([
        [
          ['Fbv4je', request, null, 'generic'],
        ],
      ]);

      final decodedResponse = await _client
          .post(
            Uri.https('news.google.com', '/_/DotsSplashUi/data/batchexecute'),
            headers: const {
              'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
              'user-agent': 'Mozilla/5.0 HAVEN/1.0',
            },
            body: {'f.req': payload},
          )
          .timeout(const Duration(seconds: 10));
      if (decodedResponse.statusCode < 200 ||
          decodedResponse.statusCode >= 300) {
        return uri;
      }

      final match = RegExp(
        r'https?:\/\/[^"\\]+',
      ).firstMatch(decodedResponse.body);
      final rawUrl = match?.group(0);
      if (rawUrl == null) return uri;

      final decodedUrl = rawUrl.replaceAll(r'\/', '/');
      return Uri.tryParse(decodedUrl) ?? uri;
    } catch (_) {
      return uri;
    }
  }

  String _extractReadableText(String html) {
    final document = html_parser.parse(html);
    final structuredText = _extractStructuredArticleText(document);
    if (structuredText.length >= 300) return structuredText;

    document
        .querySelectorAll('script, style, noscript, svg, header, nav, footer')
        .forEach((element) => element.remove());

    final primaryText = _extractFromSelectors(document, const [
      'article p',
      'main p',
      '[itemprop="articleBody"] p',
      '[class*="article"] p',
      '[class*="story"] p',
      '[class*="content"] p',
      '[class*="body"] p',
    ]);
    if (primaryText.length >= 300) return primaryText;

    final paragraphText = _cleanLines(
      document.querySelectorAll('p').map((element) => element.text),
    );
    if (paragraphText.length >= 300) return paragraphText;

    final metadataText = _extractMetadataText(document);
    if (metadataText.isNotEmpty) return metadataText;

    return primaryText.isNotEmpty ? primaryText : paragraphText;
  }

  String _extractStructuredArticleText(dom.Document document) {
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      final text = _findJsonString(jsonSource: script.text, key: 'articleBody');
      if (text != null && text.trim().length >= 300) {
        return _cleanLines(text.split(RegExp(r'\n+')));
      }
    }
    return '';
  }

  String _extractFromSelectors(dom.Document document, List<String> selectors) {
    final lines = <String>[];
    for (final selector in selectors) {
      lines.addAll(
        document.querySelectorAll(selector).map((element) => element.text),
      );
    }
    return _cleanLines(lines);
  }

  String _extractMetadataText(dom.Document document) {
    final values = [
      document
          .querySelector('meta[property="article:body"]')
          ?.attributes['content'],
      document
          .querySelector('meta[property="og:description"]')
          ?.attributes['content'],
      document.querySelector('meta[name="description"]')?.attributes['content'],
    ].whereType<String>();
    return _cleanLines(values);
  }

  String? _findJsonString({required String jsonSource, required String key}) {
    try {
      return _findJsonStringValue(jsonDecode(jsonSource), key);
    } catch (_) {
      return null;
    }
  }

  String? _findJsonStringValue(Object? value, String key) {
    if (value is Map) {
      final direct = value[key];
      if (direct is String && direct.trim().isNotEmpty) return direct;
      for (final child in value.values) {
        final found = _findJsonStringValue(child, key);
        if (found != null) return found;
      }
    }
    if (value is List) {
      for (final child in value) {
        final found = _findJsonStringValue(child, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  String _cleanLines(Iterable<String> lines) {
    final seen = <String>{};
    final cleaned = <String>[];
    for (final line in lines) {
      final normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length <= 35 || _looksLikeBoilerplate(normalized)) {
        continue;
      }
      final dedupeKey = normalized.toLowerCase();
      if (seen.add(dedupeKey)) cleaned.add(normalized);
    }
    return cleaned.join('\n\n').trim();
  }

  bool _looksLikeBoilerplate(String line) {
    final normalized = line.toLowerCase();
    const blocked = [
      'sign up',
      'subscribe',
      'cookie',
      'privacy policy',
      'terms of use',
      'advertisement',
      'enable javascript',
      'all rights reserved',
      'follow us',
      'share this',
    ];
    return blocked.any(normalized.contains);
  }
}
