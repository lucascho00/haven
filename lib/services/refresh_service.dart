import 'package:connectivity_plus/connectivity_plus.dart';

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
    final location =
        await _locationService.getCurrentLocation() ??
        HavenCache.getLastLocation();
    await HavenCache.saveManuals(_manualService.manualsFor(location));

    final connectivity = await Connectivity().checkConnectivity();
    final online = !connectivity.contains(ConnectivityResult.none);
    if (!online || location == null) {
      await HavenCache.markRefreshed();
      return RefreshResult(
        location: location,
        online: online,
        newsCount: HavenCache.getNews().length,
        safePlaceCount: HavenCache.getSafePlaces().length,
      );
    }

    final news = await _newsService.fetchLocalNews(location);
    await HavenCache.saveNews(news);

    final safePlaces = await _safePlaceService.fetchNearby(location);
    await HavenCache.saveSafePlaces(safePlaces);
    await HavenCache.markRefreshed();

    return RefreshResult(
      location: location,
      online: online,
      newsCount: news.length,
      safePlaceCount: safePlaces.length,
    );
  }
}
