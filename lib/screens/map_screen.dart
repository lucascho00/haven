import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_location.dart';
import '../models/safe_place.dart';
import '../services/location_service.dart';
import '../services/navigation_service.dart';
import '../services/refresh_service.dart';
import '../services/safe_place_service.dart';
import '../storage/haven_cache.dart';
import '../ui/glass_theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final Set<PlaceCategory> _enabledCategories = PlaceCategory.values.toSet();
  List<SafePlace> _allPlaces = [];
  AppLocation? _userLocation;
  bool _refreshing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _allPlaces = HavenCache.getSafePlaces();
    _userLocation = HavenCache.getLastLocation() ?? LocationService.defaultLocation;
    if (_allPlaces.isEmpty) {
      _refresh();
    }
    NavigationService.instance.mapFocus.addListener(_onMapFocusIntent);
    // Apply any focus that was already set before this screen mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onMapFocusIntent());
  }

  @override
  void dispose() {
    NavigationService.instance.mapFocus.removeListener(_onMapFocusIntent);
    _mapController.dispose();
    super.dispose();
  }

  void _onMapFocusIntent() {
    final intent = NavigationService.instance.mapFocus.value;
    if (intent == null || !mounted) return;

    setState(() {
      final category = intent.category;
      if (category != null) {
        // Show only the requested category.
        _enabledCategories
          ..clear()
          ..add(category);
      }
    });

    // Re-frame after the next paint so marker positions are settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _frameForIntent(intent);
      // Consume the intent so re-mounting the tab doesn't re-fire it.
      NavigationService.instance.clearMapFocus();
    });
  }

  void _frameForIntent(MapFocusIntent intent) {
    if (intent.placeId != null) {
      final match = _allPlaces.cast<SafePlace?>().firstWhere(
            (p) => p?.id == intent.placeId,
            orElse: () => null,
          );
      if (match != null) {
        _mapController.move(LatLng(match.latitude, match.longitude), 15);
        return;
      }
    }
    final cat = intent.category;
    if (cat != null) {
      final points = _allPlaces
          .where((p) => p.category == cat)
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();
      if (points.isEmpty) return;
      if (points.length == 1) {
        _mapController.move(points.first, 14);
      } else {
        _fitToPoints(points);
      }
    }
  }

  void _fitToPoints(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(72),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _status = null;
    });
    try {
      final result = await RefreshService().refreshAll();
      if (!mounted) return;
      final places = HavenCache.getSafePlaces();
      setState(() {
        _allPlaces = places;
        _userLocation = result.location ?? _userLocation;
        _status = result.online
            ? '${places.length} places cached in ${result.location?.label ?? 'the current area'}.'
            : 'Offline. Showing ${places.length} cached places.';
      });
      // Re-center on user when we have a fresh fix.
      final loc = _userLocation;
      if (loc != null) {
        _mapController.move(LatLng(loc.latitude, loc.longitude), 13);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Refresh failed. Showing ${_allPlaces.length} cached places.';
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  List<SafePlace> get _visiblePlaces => _allPlaces
      .where((p) => _enabledCategories.contains(p.category))
      .toList();

  void _centerOnUser() {
    final loc = _userLocation ?? LocationService.defaultLocation;
    _mapController.move(LatLng(loc.latitude, loc.longitude), 14);
  }

  @override
  Widget build(BuildContext context) {
    final loc = _userLocation ?? LocationService.defaultLocation;
    final center = LatLng(loc.latitude, loc.longitude);
    final places = _visiblePlaces;

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 13,
                minZoom: 4,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.haven.app',
                  maxZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    _userLocationMarker(center),
                    for (final place in places)
                      _placeMarker(place, onTap: () => _showPlaceSheet(place)),
                  ],
                ),
                const _AttributionFooter(),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _OverlayHeader(
            location: loc,
            visibleCount: places.length,
            totalCount: _allPlaces.length,
            refreshing: _refreshing,
            status: _status,
            onRefresh: _refresh,
          ),
        ),
        Positioned(
          right: 12,
          bottom: 72,
          child: _CenterMeButton(onPressed: _centerOnUser),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _CategoryFilterStrip(
            enabled: _enabledCategories,
            counts: _categoryCounts,
            onToggle: (cat) => setState(() {
              if (!_enabledCategories.add(cat)) _enabledCategories.remove(cat);
            }),
          ),
        ),
      ],
    );
  }

  Map<PlaceCategory, int> get _categoryCounts {
    final counts = <PlaceCategory, int>{};
    for (final p in _allPlaces) {
      counts.update(p.category, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Marker _userLocationMarker(LatLng center) => Marker(
    point: center,
    width: 26,
    height: 26,
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GlassColors.cyan,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: GlassColors.cyan.withValues(alpha: 0.45),
            blurRadius: 12,
          ),
        ],
      ),
    ),
  );

  Marker _placeMarker(SafePlace place, {required VoidCallback onTap}) => Marker(
    point: LatLng(place.latitude, place.longitude),
    width: 36,
    height: 36,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: place.category.color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(place.category.icon, color: Colors.white, size: 18),
      ),
    ),
  );

  void _showPlaceSheet(SafePlace place) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => _PlaceDetailsSheet(
        initialPlace: place,
        userLocation: _userLocation,
      ),
    );
  }
}

class _OverlayHeader extends StatelessWidget {
  const _OverlayHeader({
    required this.location,
    required this.visibleCount,
    required this.totalCount,
    required this.refreshing,
    required this.status,
    required this.onRefresh,
  });

  final AppLocation location;
  final int visibleCount;
  final int totalCount;
  final bool refreshing;
  final String? status;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      borderRadius: 22,
      opacity: 0.22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.label,
                      style: const TextStyle(
                        color: GlassColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      visibleCount == totalCount
                          ? '$totalCount places · 15 km radius'
                          : '$visibleCount of $totalCount places shown',
                      style: const TextStyle(
                        color: GlassColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              refreshing
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : GlassIconButton(
                      icon: Icons.refresh,
                      onPressed: onRefresh,
                      color: GlassColors.textPrimary,
                    ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 6),
            Text(
              status!,
              style: const TextStyle(color: GlassColors.safe, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryFilterStrip extends StatelessWidget {
  const _CategoryFilterStrip({
    required this.enabled,
    required this.counts,
    required this.onToggle,
  });

  final Set<PlaceCategory> enabled;
  final Map<PlaceCategory, int> counts;
  final ValueChanged<PlaceCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    final categories = PlaceCategory.values
        .where((c) => (counts[c] ?? 0) > 0)
        .toList();
    if (categories.isEmpty) return const SizedBox.shrink();

    return GlassPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      borderRadius: 22,
      opacity: 0.22,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final cat in categories)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CategoryChip(
                  category: cat,
                  active: enabled.contains(cat),
                  count: counts[cat] ?? 0,
                  onTap: () => onToggle(cat),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.active,
    required this.count,
    required this.onTap,
  });

  final PlaceCategory category;
  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? color : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          children: [
            Icon(
              category.icon,
              size: 14,
              color: active ? Colors.white : GlassColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '${category.displayName} · $count',
              style: TextStyle(
                color: active ? Colors.white : GlassColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterMeButton extends StatelessWidget {
  const _CenterMeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GlassColors.cyan.withValues(alpha: 0.92),
          border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.my_location, color: Colors.white, size: 22),
      ),
    );
  }
}

class _AttributionFooter extends StatelessWidget {
  const _AttributionFooter();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 60),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            '© OpenStreetMap',
            style: TextStyle(color: Colors.white, fontSize: 9),
          ),
        ),
      ),
    );
  }
}

class _PlaceDetailsSheet extends StatefulWidget {
  const _PlaceDetailsSheet({
    required this.initialPlace,
    required this.userLocation,
  });

  final SafePlace initialPlace;
  final AppLocation? userLocation;

  @override
  State<_PlaceDetailsSheet> createState() => _PlaceDetailsSheetState();
}

class _PlaceDetailsSheetState extends State<_PlaceDetailsSheet> {
  late SafePlace _place;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    _place = widget.initialPlace;
  }

  Future<void> _fetchRoute() async {
    final from = widget.userLocation;
    if (from == null || _routing) return;
    setState(() => _routing = true);
    try {
      final routed = await SafePlaceService().routeOnce(from, _place);
      if (!mounted) return;
      if (routed != null) {
        setState(() => _place = routed);
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _place.category;
    final route = _place.routeDurationSeconds;
    final routeDist = _place.routeDistanceMeters ?? _place.distanceMeters;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GlassPanel(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(20),
        borderRadius: 32,
        opacity: 0.24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: category.color,
                  ),
                  child: Icon(category.icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _place.name,
                        style: const TextStyle(
                          color: GlassColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _place.type,
                        style: const TextStyle(
                          color: GlassColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_place.distanceMeters != null)
                  GlassPill(
                    icon: Icons.near_me_outlined,
                    label: '${(_place.distanceMeters! / 1000).toStringAsFixed(1)} km',
                    color: GlassColors.textSecondary,
                  ),
                if (route != null)
                  GlassPill(
                    icon: Icons.route_outlined,
                    label: '${(route / 60).round()} min drive',
                    color: GlassColors.safe,
                  ),
                if (routeDist != null && _place.routeDistanceMeters != null)
                  GlassPill(
                    icon: Icons.alt_route_outlined,
                    label: '${(_place.routeDistanceMeters! / 1000).toStringAsFixed(1)} km road',
                    color: GlassColors.cyan,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${_place.latitude.toStringAsFixed(5)}, ${_place.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: GlassColors.textTertiary, fontSize: 11),
            ),
            const SizedBox(height: 16),
            if (route == null)
              GestureDetector(
                onTap: _routing ? null : _fetchRoute,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: GlassColors.emergency.withValues(alpha: 0.85),
                  ),
                  child: Center(
                    child: _routing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Get fastest route',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
