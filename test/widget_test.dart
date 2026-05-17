import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:haven/main.dart';
import 'package:haven/models/manual_item.dart';
import 'package:haven/models/news_article.dart';
import 'package:haven/services/article_content_service.dart';
import 'package:haven/services/news_service.dart';
import 'package:haven/storage/haven_cache.dart';

void main() {
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('haven_test_');
    await HavenCache.init(path: tempDir.path);
    await HavenCache.saveManuals(const [
      ManualItem(
        id: 'test-manual',
        title: 'Test Manual',
        category: 'test',
        summary: 'Keeps widget tests offline.',
        steps: ['Stay calm.'],
        priority: 1,
      ),
    ]);
  });

  testWidgets('HAVEN app renders tab shell', (WidgetTester tester) async {
    await tester.pumpWidget(const HavenApp(refreshOnOpen: false));
    await tester.pump();

    expect(find.text('HAVEN'), findsOneWidget);
    expect(find.text('MANUALS'), findsOneWidget);
    expect(find.text('Manuals'), findsWidgets);
    expect(find.text('News'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
  });

  test('long article URLs use Hive-safe cache keys', () async {
    final longUrl =
        'https://example.com/${List.filled(40, 'long-path-segment').join('/')}/article';
    final article = NewsArticle(
      id: NewsService.stableArticleId(longUrl),
      title: 'Long URL article',
      source: 'Test',
      url: longUrl,
      summary: 'Summary',
      publishedAt: DateTime(2026),
      fetchedAt: DateTime(2026),
    );

    expect(article.id.length, lessThan(255));
    await HavenCache.saveNewsArticle(article);

    expect(
      HavenCache.getNews().any((cached) => cached.id == article.id),
      isTrue,
    );
  });

  test('full content is fetched for every refreshed article', () async {
    final contentService = _FakeArticleContentService();
    final service = NewsService(articleContentService: contentService);
    final articles = List.generate(
      5,
      (index) => NewsArticle(
        id: 'article-$index',
        title: 'Article $index',
        source: 'Test',
        url: 'https://example.com/article-$index',
        summary: 'Summary $index',
        publishedAt: DateTime(2026, 1, index + 1),
        fetchedAt: DateTime(2026),
      ),
    );

    final updated = await service.fetchFullContentForArticles(articles);

    expect(contentService.fetchedIds, articles.map((article) => article.id));
    expect(updated, hasLength(articles.length));
    expect(updated.every((article) => article.content != null), isTrue);
  });

  test('article content extraction reads publisher paragraphs', () async {
    final article = _testArticle(url: 'https://example.com/article');
    final service = ArticleContentService(
      client: MockClient((request) async {
        return http.Response(_articleHtml('Publisher paragraph'), 200);
      }),
    );

    final updated = await service.fetchFullContent(article);

    expect(updated.contentStatus, 'Full text extracted from source page.');
    expect(updated.content, contains('Publisher paragraph 0'));
    expect(updated.content!.length, greaterThan(300));
  });

  test('Google News URLs are resolved before extracting article text', () async {
    final googleUrl =
        'https://news.google.com/rss/articles/google-article-token?oc=5';
    final publisherUrl = 'https://publisher.example.com/story';
    final article = _testArticle(url: googleUrl);
    final service = ArticleContentService(
      client: MockClient((request) async {
        if (request.url.host == 'news.google.com' && request.method == 'GET') {
          return http.Response(
            '<html><body><c-wiz><div data-n-a-sg="signature" data-n-a-ts="123"></div></c-wiz></body></html>',
            200,
          );
        }
        if (request.url.host == 'news.google.com' && request.method == 'POST') {
          final rpcPayload = jsonEncode(['garturlres', publisherUrl, 1]);
          return http.Response(
            ''')]}'
[["wrb.fr","Fbv4je",${jsonEncode(rpcPayload)},null,null,null,"generic"]]''',
            200,
          );
        }
        if (request.url.toString() == publisherUrl) {
          return http.Response(
            _articleHtml('Resolved publisher paragraph'),
            200,
          );
        }
        return http.Response(
          'unexpected ${request.method} ${request.url}',
          404,
        );
      }),
    );

    final updated = await service.fetchFullContent(article);

    expect(updated.url, publisherUrl);
    expect(updated.contentStatus, 'Full text extracted from source page.');
    expect(updated.content, contains('Resolved publisher paragraph 0'));
  });
}

NewsArticle _testArticle({required String url}) {
  return NewsArticle(
    id: NewsService.stableArticleId(url),
    title: 'Test article',
    source: 'Test',
    url: url,
    summary: 'Summary',
    publishedAt: DateTime(2026),
    fetchedAt: DateTime(2026),
  );
}

String _articleHtml(String prefix) {
  final paragraphs = List.generate(
    8,
    (index) =>
        '<p>$prefix $index has enough realistic article text to pass the readable extraction threshold and remain useful offline.</p>',
  ).join();
  return '<html><body><article>$paragraphs</article></body></html>';
}

class _FakeArticleContentService implements ArticleContentService {
  final fetchedIds = <String>[];

  @override
  Future<NewsArticle> fetchFullContent(NewsArticle article) async {
    fetchedIds.add(article.id);
    return article.copyWith(
      content: 'Full content for ${article.id}',
      contentFetchedAt: DateTime(2026),
      contentStatus: 'Fetched in test.',
    );
  }
}
