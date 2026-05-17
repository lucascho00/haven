import '../models/app_location.dart';
import '../storage/haven_cache.dart';

class LocationService {
  static AppLocation get defaultLocation => AppLocation(
    latitude: 35.6892,
    longitude: 51.3890,
    city: 'Tehran',
    region: 'Tehran Province',
    country: 'Iran',
    updatedAt: DateTime.now(),
  );

  Future<AppLocation?> getCurrentLocation() async {
    final location = defaultLocation;
    await HavenCache.saveLastLocation(location);
    return location;
  }
}
