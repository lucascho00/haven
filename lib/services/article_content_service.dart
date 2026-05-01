import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/news_article.dart';

class ArticleContentService {
  Future<NewsArticle> fetchFullContent(NewsArticle article) async {
    if ((article.content ?? '').trim().length > 300) {
      return article;
    }

    try {
      final response = await http
          .get(
            Uri.parse(article.url),
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
          contentStatus: 'Source returned HTTP ${response.statusCode}.',
          contentFetchedAt: DateTime.now(),
        );
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final extracted = _extractReadableText(html);
      if (extracted.length < 300) {
        return article.copyWith(
          content: extracted.isEmpty ? null : extracted,
          contentStatus:
              'Could not extract enough readable article text from this source.',
          contentFetchedAt: DateTime.now(),
        );
      }

      return article.copyWith(
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

  String _extractReadableText(String html) {
    var text = html
        .replaceAll(_htmlBlock('script'), ' ')
        .replaceAll(_htmlBlock('style'), ' ')
        .replaceAll(_htmlBlock('noscript'), ' ')
        .replaceAll(_htmlBlock('svg'), ' ')
        .replaceAll(_htmlBlock('header'), ' ')
        .replaceAll(_htmlBlock('nav'), ' ')
        .replaceAll(_htmlBlock('footer'), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>', caseSensitive: false, dotAll: true), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');

    text = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.length > 35)
        .where((line) => !_looksLikeBoilerplate(line))
        .join('\n\n');

    if (text.length > 12000) {
      return '${text.substring(0, 12000).trim()}\n\n[Truncated for offline storage]';
    }
    return text.trim();
  }

  RegExp _htmlBlock(String tag) =>
      RegExp('<$tag[^>]*>.*?</$tag>', caseSensitive: false, dotAll: true);

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
