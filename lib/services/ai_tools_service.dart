import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/tool.dart';

import '../models/safe_place.dart';
import '../storage/haven_cache.dart';

/// Catalog of native function-calling tools the on-device Gemma 4 model can
/// invoke. Each tool reads only from the local Hive cache — never the network
/// — so the model stays grounded in what is actually available offline.
class AiToolsService {
  /// JSON-schema-style tool declarations passed to `createChat(tools: ...)`.
  List<Tool> get tools => const [
        Tool(
          name: 'get_safe_places',
          description:
              'List cached safe places within 15 km of the user, optionally filtered by category. '
              'Use this when the user asks about nearby hospitals, shelters, schools, water, markets, '
              'pharmacies, police, fire stations, embassies, fuel stations, ATMs, transit, or other '
              'safe locations. Returned places already include cached drive-time when known.',
          parameters: {
            'type': 'OBJECT',
            'properties': {
              'category': {
                'type': 'STRING',
                'description':
                    'Category filter. Omit to return all categories. '
                    'One of: hospital, pharmacy, police, fire, shelter, school, community, market, '
                    'water, worship, embassy, fuel, transit, bank, atm.',
              },
              'max_results': {
                'type': 'INTEGER',
                'description': 'Maximum number of places to return. Defaults to 5.',
              },
            },
            'required': <String>[],
          },
        ),
        Tool(
          name: 'find_nearest',
          description:
              'Return the single closest cached place in a given category (e.g., nearest hospital). '
              'Use when the user asks "where is the nearest X" and only needs one specific answer.',
          parameters: {
            'type': 'OBJECT',
            'properties': {
              'category': {
                'type': 'STRING',
                'description':
                    'Required. One of: hospital, pharmacy, police, fire, shelter, school, '
                    'community, market, water, worship, embassy, fuel, transit, bank, atm.',
              },
            },
            'required': <String>['category'],
          },
        ),
        Tool(
          name: 'get_news_article',
          description:
              'Fetch the full cached text of one recent local news article whose title best matches '
              'the search query. Use this when the user asks for details about a specific news '
              'story you saw a headline for in the system context.',
          parameters: {
            'type': 'OBJECT',
            'properties': {
              'query': {
                'type': 'STRING',
                'description':
                    'Free-text fragment to match against article titles (case-insensitive).',
              },
            },
            'required': <String>['query'],
          },
        ),
        Tool(
          name: 'summarize_news',
          description:
              'Pull cached news articles whose title or summary matches a topic and return their '
              'titles + short excerpts so you can synthesize a multi-source summary. Use when the '
              'user asks for a roundup of news on a specific topic.',
          parameters: {
            'type': 'OBJECT',
            'properties': {
              'topic': {
                'type': 'STRING',
                'description':
                    'Free-text topic, e.g., "ceasefire", "Hormuz", "evacuation". Case-insensitive.',
              },
              'max_articles': {
                'type': 'INTEGER',
                'description': 'How many matching articles to include. Defaults to 4.',
              },
            },
            'required': <String>['topic'],
          },
        ),
        Tool(
          name: 'assess_current_risks',
          description:
              'Scan all cached news headlines for risk keywords (airstrike, attack, drone, evacuation, '
              'ceasefire, blockade, shelling, raid, blast) and return structured counts plus the '
              'matching headlines. Use this to give the user a quick situational read.',
          parameters: {
            'type': 'OBJECT',
            'properties': <String, dynamic>{},
            'required': <String>[],
          },
        ),
        Tool(
          name: 'get_manual_steps',
          description:
              'Return the full numbered step list for a cached survival manual. Use this when the '
              'user asks how to handle a specific emergency that matches one of the available '
              'manuals (airstrike, evacuation, severe bleeding, chemical/smoke, earthquake, flood).',
          parameters: {
            'type': 'OBJECT',
            'properties': {
              'manual_id': {
                'type': 'STRING',
                'description':
                    'Manual identifier. One of: airstrike-shelter, evacuation-route, '
                    'bleeding-trauma, chemical-smoke, earthquake, flood. If unsure, pass a '
                    'partial title and we will match the closest one.',
              },
            },
            'required': <String>['manual_id'],
          },
        ),
      ];

  /// Execute the tool against the local Hive cache and return a JSON-friendly
  /// map that gets serialised into a `Message.toolResponse` sent back to the
  /// model. Always returns a map — even on error — so the model can recover.
  Map<String, dynamic> execute(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'get_safe_places':
        return _getSafePlaces(args);
      case 'find_nearest':
        return _findNearest(args);
      case 'get_news_article':
        return _getNewsArticle(args);
      case 'summarize_news':
        return _summarizeNews(args);
      case 'assess_current_risks':
        return _assessCurrentRisks(args);
      case 'get_manual_steps':
        return _getManualSteps(args);
      default:
        return {'error': 'Unknown tool: $name'};
    }
  }

  /// Convenience: convert an executed result into the `Message.toolResponse`
  /// shape flutter_gemma's chat session expects.
  Message toolResponse(String name, Map<String, dynamic> response) {
    return Message.toolResponse(toolName: name, response: response);
  }

  Map<String, dynamic> _getSafePlaces(Map<String, dynamic> args) {
    final categoryArg = (args['category'] as String?)?.trim().toLowerCase();
    final maxResults = (args['max_results'] as num?)?.toInt() ?? 5;

    PlaceCategory? filter;
    if (categoryArg != null && categoryArg.isNotEmpty) {
      filter = PlaceCategory.values
          .where((c) => c.name == categoryArg)
          .cast<PlaceCategory?>()
          .firstWhere((_) => true, orElse: () => null);
    }

    final all = HavenCache.getSafePlaces();
    final filtered = filter == null
        ? all
        : all.where((p) => p.category == filter).toList();

    final results = filtered.take(maxResults.clamp(1, 20)).map((p) {
      return {
        'name': p.name,
        'type': p.type,
        'category': p.category.name,
        'latitude': p.latitude,
        'longitude': p.longitude,
        if (p.routeDurationSeconds != null)
          'drive_minutes': (p.routeDurationSeconds! / 60).round(),
        if (p.distanceMeters != null)
          'distance_km': (p.distanceMeters! / 1000).toStringAsFixed(2),
      };
    }).toList();

    return {
      'count': results.length,
      'total_available': filtered.length,
      'requested_category': categoryArg ?? 'any',
      'places': results,
    };
  }

  Map<String, dynamic> _findNearest(Map<String, dynamic> args) {
    final categoryArg = (args['category'] as String?)?.trim().toLowerCase();
    if (categoryArg == null || categoryArg.isEmpty) {
      return {'error': 'category parameter required'};
    }
    final filter = PlaceCategory.values
        .where((c) => c.name == categoryArg)
        .cast<PlaceCategory?>()
        .firstWhere((_) => true, orElse: () => null);
    if (filter == null) {
      return {
        'found': false,
        'reason': 'Unknown category. Valid: '
            '${PlaceCategory.values.map((c) => c.name).join(', ')}',
      };
    }
    final places = HavenCache.getSafePlaces().where((p) => p.category == filter);
    if (places.isEmpty) {
      return {'found': false, 'category': categoryArg};
    }
    final nearest = places.first; // HavenCache already sorts by route then distance.
    return {
      'found': true,
      'name': nearest.name,
      'type': nearest.type,
      'category': nearest.category.name,
      'latitude': nearest.latitude,
      'longitude': nearest.longitude,
      if (nearest.routeDurationSeconds != null)
        'drive_minutes': (nearest.routeDurationSeconds! / 60).round(),
      if (nearest.distanceMeters != null)
        'distance_km': (nearest.distanceMeters! / 1000).toStringAsFixed(2),
    };
  }

  Map<String, dynamic> _summarizeNews(Map<String, dynamic> args) {
    final topic = ((args['topic'] as String?) ?? '').trim().toLowerCase();
    final maxArticles = (args['max_articles'] as num?)?.toInt() ?? 4;
    if (topic.isEmpty) {
      return {'error': 'topic parameter required'};
    }
    final matches = HavenCache.getNews()
        .where(
          (a) =>
              a.title.toLowerCase().contains(topic) ||
              a.summary.toLowerCase().contains(topic),
        )
        .take(maxArticles.clamp(1, 8))
        .toList();
    if (matches.isEmpty) {
      return {'found': false, 'topic': topic};
    }
    return {
      'found': true,
      'topic': topic,
      'count': matches.length,
      'articles': [
        for (final a in matches)
          {
            'title': a.title,
            'source': a.source,
            'excerpt': () {
              final body = (a.content?.trim().isNotEmpty ?? false)
                  ? a.content!.trim()
                  : a.summary.trim();
              return body.length > 600 ? '${body.substring(0, 600)}...' : body;
            }(),
          },
      ],
    };
  }

  Map<String, dynamic> _assessCurrentRisks(Map<String, dynamic> args) {
    const riskKeywords = [
      'airstrike',
      'air strike',
      'attack',
      'attacked',
      'strike',
      'drone',
      'missile',
      'shelling',
      'shelled',
      'blast',
      'explosion',
      'raid',
      'blockade',
      'siege',
      'evacuat',
      'ceasefire',
      'truce',
      'casualt',
      'wounded',
      'killed',
    ];
    final news = HavenCache.getNews();
    final matchedByKeyword = <String, List<String>>{};
    for (final article in news) {
      final hay = '${article.title} ${article.summary}'.toLowerCase();
      for (final kw in riskKeywords) {
        if (hay.contains(kw)) {
          matchedByKeyword.putIfAbsent(kw, () => []).add(article.title);
        }
      }
    }
    final summary = matchedByKeyword.entries
        .map(
          (e) => {
            'keyword': e.key,
            'count': e.value.length,
            'sample_titles': e.value.take(2).toList(),
          },
        )
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return {
      'total_articles_scanned': news.length,
      'keywords_with_hits': summary.length,
      'breakdown': summary,
    };
  }

  Map<String, dynamic> _getNewsArticle(Map<String, dynamic> args) {
    final query = ((args['query'] as String?) ?? '').trim().toLowerCase();
    if (query.isEmpty) {
      return {'error': 'query parameter required'};
    }

    final news = HavenCache.getNews();
    final match = news.cast<dynamic>().firstWhere(
          (a) => a.title.toString().toLowerCase().contains(query),
          orElse: () => null,
        );
    if (match == null) {
      return {'found': false, 'query': query};
    }

    final content = (match.content as String?)?.trim();
    final summary = (match.summary as String?)?.trim() ?? '';
    final body = (content != null && content.isNotEmpty) ? content : summary;
    final truncated =
        body.length > 1500 ? '${body.substring(0, 1500)}...' : body;

    return {
      'found': true,
      'title': match.title,
      'source': match.source,
      'published_at': match.publishedAt.toIso8601String(),
      'url': match.url,
      'body': truncated,
    };
  }

  Map<String, dynamic> _getManualSteps(Map<String, dynamic> args) {
    final idArg = ((args['manual_id'] as String?) ?? '').trim().toLowerCase();
    if (idArg.isEmpty) {
      return {'error': 'manual_id parameter required'};
    }

    final manuals = HavenCache.getManuals();
    // Exact id match first, then partial-title fallback.
    final exact = manuals.where((m) => m.id.toLowerCase() == idArg).toList();
    final match = exact.isNotEmpty
        ? exact.first
        : manuals
            .where(
              (m) =>
                  m.id.toLowerCase().contains(idArg) ||
                  m.title.toLowerCase().contains(idArg),
            )
            .cast<dynamic>()
            .firstWhere((_) => true, orElse: () => null);

    if (match == null) {
      return {
        'found': false,
        'requested_id': idArg,
        'available_ids': manuals.map((m) => m.id).toList(),
      };
    }

    return {
      'found': true,
      'id': match.id,
      'title': match.title,
      'category': match.category,
      'summary': match.summary,
      'steps': match.steps,
    };
  }
}
