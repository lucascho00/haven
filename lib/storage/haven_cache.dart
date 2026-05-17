import 'package:hive_flutter/hive_flutter.dart';

import '../models/app_location.dart';
import '../models/manual_item.dart';
import '../models/news_article.dart';
import '../models/safe_place.dart';

class HavenCache {
  static const _manualsBox = 'manuals';
  static const _safePlacesBox = 'safe_places';
  static const _newsBox = 'news_articles';
  static const _settingsBox = 'settings';
  static const _locationKey = 'last_location';
  static const _refreshKey = 'last_refresh';
  static const _backendKey = 'agent_backend';

  static Future<void> init({String? path}) async {
    if (path == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(path);
    }
    await Future.wait([
      Hive.openBox<Map>(_manualsBox),
      Hive.openBox<Map>(_safePlacesBox),
      Hive.openBox<Map>(_newsBox),
      Hive.openBox<Map>(_settingsBox),
    ]);
  }

  static Box<Map> get _manuals => Hive.box<Map>(_manualsBox);
  static Box<Map> get _safePlaces => Hive.box<Map>(_safePlacesBox);
  static Box<Map> get _news => Hive.box<Map>(_newsBox);
  static Box<Map> get _settings => Hive.box<Map>(_settingsBox);

  static List<ManualItem> getManuals() {
    final manuals = _manuals.values.map(ManualItem.fromJson).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return manuals;
  }

  static Future<void> saveManuals(List<ManualItem> manuals) async {
    await _manuals.clear();
    await _manuals.putAll({
      for (final manual in manuals) manual.id: manual.toJson(),
    });
  }

  static List<SafePlace> getSafePlaces() {
    final places = _safePlaces.values.map(SafePlace.fromJson).toList()
      ..sort((a, b) {
        final routeA = a.routeDurationSeconds ?? double.infinity;
        final routeB = b.routeDurationSeconds ?? double.infinity;
        final routeCompare = routeA.compareTo(routeB);
        if (routeCompare != 0) return routeCompare;
        return (a.distanceMeters ?? double.infinity).compareTo(
          b.distanceMeters ?? double.infinity,
        );
      });
    return places;
  }

  static Future<void> saveSafePlaces(List<SafePlace> places) async {
    await _safePlaces.clear();
    await _safePlaces.putAll({
      for (final place in places) place.id: place.toJson(),
    });
  }

  static List<NewsArticle> getNews() {
    final articles = _news.values.map(NewsArticle.fromJson).toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return articles;
  }

  static Future<void> saveNews(List<NewsArticle> articles) async {
    final current = {for (final article in getNews()) article.id: article};
    final mergedArticles = articles.map((article) {
      final existing = current[article.id];
      if (existing == null || article.content != null) return article;
      return article.copyWith(
        content: existing.content,
        contentFetchedAt: existing.contentFetchedAt,
        contentStatus: existing.contentStatus,
      );
    });
    final existing = {
      for (final article in current.values) article.id: article,
      for (final article in mergedArticles) article.id: article,
    };
    final sorted = existing.values.toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final trimmed = sorted.take(80).toList();
    await _news.clear();
    await _news.putAll({
      for (final article in trimmed) article.id: article.toJson(),
    });
  }

  static Future<void> saveNewsArticle(NewsArticle article) async {
    await _news.put(article.id, article.toJson());
  }

  static AppLocation? getLastLocation() {
    final json = _settings.get(_locationKey);
    return json == null ? null : AppLocation.fromJson(json);
  }

  static Future<void> saveLastLocation(AppLocation location) async {
    await _settings.put(_locationKey, location.toJson());
  }

  static DateTime? getLastRefresh() {
    final json = _settings.get(_refreshKey);
    final value = json?['value'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  static Future<void> markRefreshed() async {
    await _settings.put(_refreshKey, {
      'value': DateTime.now().toIso8601String(),
    });
  }

  /// Preferred Gemma 4 backend: 'auto', 'gpu', or 'cpu'. Defaults to 'auto'.
  static String getAgentBackend() {
    final entry = _settings.get(_backendKey);
    final value = entry?['value'] as String?;
    return value ?? 'auto';
  }

  static Future<void> saveAgentBackend(String backend) async {
    await _settings.put(_backendKey, {'value': backend});
  }
}
