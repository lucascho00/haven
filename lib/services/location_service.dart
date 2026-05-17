import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart';

import '../models/app_location.dart';
import '../storage/haven_cache.dart';

class LocationService {
  /// Fallback used when GPS is unavailable / denied. Keeps Tehran as the
  /// "demo war zone" anchor so the offline-first story still works.
  static AppLocation get defaultLocation => AppLocation(
    latitude: 35.6892,
    longitude: 51.3890,
    city: 'Tehran',
    region: 'Tehran Province',
    country: 'Iran',
    updatedAt: DateTime.now(),
  );

  /// Resolve the user's current location. Strategy:
  ///   1. Check & request location permission via geolocator.
  ///   2. Get a single GPS fix (medium accuracy, 8s timeout).
  ///   3. Reverse-geocode to populate city / region / country.
  ///   4. Persist to Hive so offline launches still see the last fix.
  /// Any failure falls back to the last cached location, then to Tehran.
  Future<AppLocation?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: device location services OFF');
        return _fallback('Location services are turned off on the device');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('LocationService: permission $permission');
        return _fallback('Location permission was denied');
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      debugPrint(
        'LocationService: GPS fix ${position.latitude}, ${position.longitude} '
        '(±${position.accuracy.toStringAsFixed(0)}m)',
      );

      String? city;
      String? region;
      String? country;
      try {
        final places = await gc.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (places.isNotEmpty) {
          final p = places.first;
          city = _firstNonEmpty([p.locality, p.subAdministrativeArea, p.name]);
          region = _firstNonEmpty([p.administrativeArea, p.subAdministrativeArea]);
          country = _firstNonEmpty([p.country, p.isoCountryCode]);
        }
      } catch (e) {
        debugPrint('LocationService: reverse geocode failed — $e');
      }

      final resolved = AppLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        city: city,
        region: region,
        country: country,
        updatedAt: DateTime.now(),
      );
      await HavenCache.saveLastLocation(resolved);
      return resolved;
    } catch (e) {
      debugPrint('LocationService: getCurrentLocation threw — $e');
      return _fallback('GPS fix failed: $e');
    }
  }

  Future<AppLocation?> _fallback(String reason) async {
    debugPrint('LocationService: falling back ($reason)');
    final cached = HavenCache.getLastLocation();
    if (cached != null) return cached;
    final fallback = defaultLocation;
    await HavenCache.saveLastLocation(fallback);
    return fallback;
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
