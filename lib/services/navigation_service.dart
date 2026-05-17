import 'package:flutter/foundation.dart';

import '../models/safe_place.dart';

/// Tab indices in [HavenHomeScreen]. Update if the tab order changes.
class HavenTabs {
  static const map = 0;
  static const news = 1;
  static const agent = 2;
  static const settings = 3;
}

/// A request to focus the Map tab on a particular category or specific place,
/// emitted by the chat agent's tool-call layer and consumed by [MapScreen].
@immutable
class MapFocusIntent {
  const MapFocusIntent({
    this.category,
    this.placeId,
    this.label,
  });

  /// If set, the map should show only this category and zoom to fit it.
  final PlaceCategory? category;

  /// If set, the map should center on this specific place.
  final String? placeId;

  /// Optional human-readable label shown in any toast/snackbar.
  final String? label;
}

/// Cross-tab navigation bus. Singleton because tabs are siblings in an
/// IndexedStack — the chat agent needs a way to ask the map to focus a
/// category, and the home screen needs a way to switch active tabs.
class NavigationService {
  NavigationService._();
  static final NavigationService instance = NavigationService._();

  final ValueNotifier<int> tabIndex = ValueNotifier<int>(HavenTabs.map);
  final ValueNotifier<MapFocusIntent?> mapFocus =
      ValueNotifier<MapFocusIntent?>(null);

  void goToMap({PlaceCategory? category, String? placeId, String? label}) {
    mapFocus.value = MapFocusIntent(
      category: category,
      placeId: placeId,
      label: label,
    );
    tabIndex.value = HavenTabs.map;
  }

  void goToSettings() {
    tabIndex.value = HavenTabs.settings;
  }

  void clearMapFocus() {
    mapFocus.value = null;
  }
}
