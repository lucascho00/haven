import '../storage/haven_cache.dart';

class AiContextService {
  /// Compact context written into the chat's system instruction ONCE at
  /// session creation. Stays in the KV cache; never re-transmitted per turn.
  /// Target: keep well under ~800 tokens. No long article excerpts here —
  /// just titles / names so the model knows what's available and can refer
  /// to specifics if the user asks.
  String buildSystemContext() {
    final location = HavenCache.getLastLocation();
    final manuals = HavenCache.getManuals();
    final safePlaces = HavenCache.getSafePlaces().take(8);
    final news = HavenCache.getNews().take(8);

    final buf = StringBuffer()
      ..writeln('--- CACHED LOCAL CONTEXT (snapshot at chat start) ---')
      ..writeln('Location: ${location?.label ?? 'unknown'}');

    if (safePlaces.isNotEmpty) {
      buf.writeln('\nNearest cached safe places (sorted by drive time):');
      for (final p in safePlaces) {
        final eta = p.routeDurationSeconds == null
            ? ''
            : ' — ~${(p.routeDurationSeconds! / 60).round()} min';
        buf.writeln('- ${p.name} [${p.type}]$eta');
      }
    }

    if (news.isNotEmpty) {
      buf.writeln('\nRecent local headlines:');
      for (final a in news) {
        buf.writeln('- ${a.title} (${a.source})');
      }
    }

    if (manuals.isNotEmpty) {
      buf.writeln('\nAvailable survival manuals:');
      for (final m in manuals) {
        buf.writeln('- ${m.title}');
      }
    }

    buf.writeln(
      '\nThe user can also open the Map tab to see all cached safe places, '
      'and the Newspaper tab for full article text.',
    );

    return buf.toString();
  }
}
