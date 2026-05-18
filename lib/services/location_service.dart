import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as gc;
import 'package:geolocator/geolocator.dart';

import '../models/app_location.dart';
import '../storage/haven_cache.dart';

/// Where HAVEN considers "here". A small list of conflict-zone demo cities
/// plus an opt-in "use my real GPS" path. The default is Tehran so the
/// out-of-the-box experience opens in a war context; nothing is hardcoded
/// past the default — users switch in Settings.
enum LocationPreset {
  tehran,
  kyiv,
  gaza,
  realGps;

  String get displayName => switch (this) {
    LocationPreset.tehran => 'Tehran, Iran',
    LocationPreset.kyiv => 'Kyiv, Ukraine',
    LocationPreset.gaza => 'Gaza City, Palestine',
    LocationPreset.realGps => 'Use my real GPS',
  };

  String get subtitle => switch (this) {
    LocationPreset.tehran =>
      'Default demo anchor — the hackathon scenario.',
    LocationPreset.kyiv => 'Ongoing armed-conflict scenario.',
    LocationPreset.gaza => 'Ongoing humanitarian-crisis scenario.',
    LocationPreset.realGps =>
      'Resolve your actual location with iOS / Android GPS.',
  };

  /// Fixed coords for the demo cities. Real GPS returns null here and is
  /// resolved at call time via geolocator.
  AppLocation? get fixedLocation {
    final now = DateTime.now();
    switch (this) {
      case LocationPreset.tehran:
        return AppLocation(
          latitude: 35.6892,
          longitude: 51.3890,
          city: 'Tehran',
          region: 'Tehran Province',
          country: 'Iran',
          updatedAt: now,
        );
      case LocationPreset.kyiv:
        return AppLocation(
          latitude: 50.4501,
          longitude: 30.5234,
          city: 'Kyiv',
          region: 'Kyiv Oblast',
          country: 'Ukraine',
          updatedAt: now,
        );
      case LocationPreset.gaza:
        return AppLocation(
          latitude: 31.5018,
          longitude: 34.4669,
          city: 'Gaza City',
          region: 'Gaza Governorate',
          country: 'Palestine',
          updatedAt: now,
        );
      case LocationPreset.realGps:
        return null;
    }
  }

  static LocationPreset fromName(String name) =>
      LocationPreset.values.firstWhere(
        (p) => p.name == name,
        orElse: () => LocationPreset.tehran,
      );
}

class LocationService {
  /// Tehran fallback, used when GPS is unavailable / denied and no preset is
  /// set yet. Keeps the demo narrative bullet-proof.
  static AppLocation get defaultLocation =>
      LocationPreset.tehran.fixedLocation!;

  /// Resolves the current location based on the user's chosen preset.
  /// Persists the result to Hive so offline launches still have an anchor.
  Future<AppLocation?> getCurrentLocation() async {
    final preset = LocationPreset.fromName(HavenCache.getLocationPreset());
    debugPrint('LocationService: preset=${preset.name}');

    if (preset != LocationPreset.realGps) {
      final loc = preset.fixedLocation!;
      await HavenCache.saveLastLocation(loc);
      return loc;
    }

    final real = await _resolveRealGps();
    if (real != null) return real;
    debugPrint('LocationService: GPS unavailable, falling back to Tehran');
    final fallback = LocationPreset.tehran.fixedLocation!;
    await HavenCache.saveLastLocation(fallback);
    return fallback;
  }

  Future<AppLocation?> _resolveRealGps() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: device location services OFF');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('LocationService: permission $permission');
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );
      String? city;
      String? region;
      String? country;
      try {
        final places = await gc.placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
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
        latitude: pos.latitude,
        longitude: pos.longitude,
        city: city,
        region: region,
        country: country,
        updatedAt: DateTime.now(),
      );
      await HavenCache.saveLastLocation(resolved);
      return resolved;
    } catch (e) {
      debugPrint('LocationService: real GPS resolution threw — $e');
      return null;
    }
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}
