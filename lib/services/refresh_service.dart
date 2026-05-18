import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/app_location.dart';
import '../storage/haven_cache.dart';
import 'location_service.dart';
import 'manual_service.dart';
import 'news_service.dart';
import 'safe_place_service.dart';

class RefreshResult {
  const RefreshResult({
    required this.location,
    required this.online,
    required this.newsCount,
    required this.safePlaceCount,
  });

  final AppLocation? location;
  final bool online;
  final int newsCount;
  final int safePlaceCount;
}

class RefreshService {
  RefreshService({
    LocationService? locationService,
    ManualService? manualService,
    NewsService? newsService,
    SafePlaceService? safePlaceService,
  }) : _locationService = locationService ?? LocationService(),
       _manualService = manualService ?? ManualService(),
       _newsService = newsService ?? NewsService(),
       _safePlaceService = safePlaceService ?? SafePlaceService();

  final LocationService _locationService;
  final ManualService _manualService;
  final NewsService _newsService;
  final SafePlaceService _safePlaceService;

  Future<RefreshResult> refreshAll() async {
    final activeRefresh = _activeRefresh;
    if (activeRefresh != null) return activeRefresh;

    final refresh = _refreshAll();
    _activeRefresh = refresh;
    return refresh.whenComplete(() {
      if (identical(_activeRefresh, refresh)) {
        _activeRefresh = null;
      }
    });
  }

  static Future<RefreshResult>? _activeRefresh;

  Future<RefreshResult> _refreshAll() async {
    // Each step is isolated so a failure in one (e.g., a slow article body
    // fetch that times out) doesn't prevent the others (e.g., safe places)
    // from running. Previously a single thrown exception anywhere in this
    // pipeline would skip every step after it — most often news fetch
    // would die mid-way and the Map tab would never see fresh POIs.

    // Step 1: resolve location.
    AppLocation? location;
    try {
      location = await _locationService.getCurrentLocation() ??
          HavenCache.getLastLocation();
      debugPrint(
        'RefreshService: location = ${location?.label} '
        '(${location?.latitude}, ${location?.longitude})',
      );
    } catch (e, st) {
      debugPrint('RefreshService: getCurrentLocation threw — $e\n$st');
      location = HavenCache.getLastLocation();
    }

    // Step 2: refresh local manuals (offline operation, always safe).
    try {
      await HavenCache.saveManuals(_manualService.manualsFor(location));
    } catch (e) {
      debugPrint('RefreshService: saveManuals failed — $e');
    }

    // Step 3: check connectivity.
    var online = false;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      online = !connectivity.contains(ConnectivityResult.none);
    } catch (e) {
      debugPrint('RefreshService: connectivity check failed — $e');
    }
    debugPrint('RefreshService: online=$online');

    if (!online || location == null) {
      await HavenCache.markRefreshed();
      return RefreshResult(
        location: location,
        online: online,
        newsCount: HavenCache.getNews().length,
        safePlaceCount: HavenCache.getSafePlaces().length,
      );
    }

    // Step 4: news fetch. Wrapped so a thrown article extractor doesn't
    // skip the safe-places step that comes after.
    var newsCount = 0;
    try {
      debugPrint('RefreshService: fetching news for ${location.label}...');
      final news = await _newsService.fetchLocalNews(location);
      debugPrint('RefreshService: news fetch returned ${news.length} articles');
      await HavenCache.saveNews(news);
      newsCount = news.length;
      debugPrint(
        'RefreshService: cache now holds '
        '${HavenCache.getNews().length} articles',
      );
    } catch (e, st) {
      debugPrint('RefreshService: news pipeline failed — $e\n$st');
    }

    // Step 5: safe-place fetch. Isolated for the same reason — Overpass /
    // OSRM hiccups must not silently strand the map.
    var safePlaceCount = 0;
    try {
      debugPrint(
        'RefreshService: fetching safe places around ${location.label}...',
      );
      final safePlaces = await _safePlaceService.fetchNearby(location);
      debugPrint(
        'RefreshService: fetchNearby returned ${safePlaces.length} places',
      );
      await HavenCache.saveSafePlaces(safePlaces);
      safePlaceCount = safePlaces.length;
      debugPrint(
        'RefreshService: cache now holds '
        '${HavenCache.getSafePlaces().length} safe places',
      );
    } catch (e, st) {
      debugPrint('RefreshService: safe-place pipeline failed — $e\n$st');
    }

    await HavenCache.markRefreshed();
    return RefreshResult(
      location: location,
      online: online,
      newsCount: newsCount,
      safePlaceCount: safePlaceCount,
    );
  }
}
