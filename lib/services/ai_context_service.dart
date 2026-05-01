import '../models/news_article.dart';
import '../storage/haven_cache.dart';

class AiContextService {
  String buildContext() {
    final location = HavenCache.getLastLocation();
    final manuals = HavenCache.getManuals().take(4);
    final safePlaces = HavenCache.getSafePlaces().take(5);
    final news = HavenCache.getNews().take(6);

    final buffer = StringBuffer()
      ..writeln('LOCAL CONTEXT SNAPSHOT')
      ..writeln('Location: ${location?.label ?? 'unknown'}');

    if (safePlaces.isNotEmpty) {
      buffer.writeln('\nNearby cached safe places:');
      for (final place in safePlaces) {
        final duration = place.routeDurationSeconds == null
            ? 'route unknown'
            : '${(place.routeDurationSeconds! / 60).round()} min route';
        buffer.writeln('- ${place.name} (${place.type}), $duration');
      }
    }

    if (news.isNotEmpty) {
      buffer.writeln('\nCached local reports:');
      for (final article in news) {
        final detail = _articleDetail(article);
        buffer.writeln('- ${article.title} [${article.source}]');
        if (detail.isNotEmpty) {
          buffer.writeln('  Context: $detail');
        }
      }
    }

    if (manuals.isNotEmpty) {
      buffer.writeln('\nRelevant manuals:');
      for (final manual in manuals) {
        buffer.writeln('- ${manual.title}: ${manual.summary}');
      }
    }

    return buffer.toString();
  }

  String _articleDetail(NewsArticle article) {
    final content = article.content?.trim();
    final summary = article.summary.trim();
    final text = content != null && content.isNotEmpty ? content : summary;
    if (text.isEmpty) return '';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 420) return normalized;
    return '${normalized.substring(0, 420)}...';
  }
}
