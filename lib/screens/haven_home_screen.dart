import 'dart:async';

import 'package:flutter/material.dart';

import '../services/navigation_service.dart';
import '../services/refresh_service.dart';
import '../ui/glass_theme.dart';
import 'chat_screen.dart';
import 'map_screen.dart';
import 'newspaper_screen.dart';
import 'settings_screen.dart';

class HavenHomeScreen extends StatefulWidget {
  const HavenHomeScreen({super.key, this.refreshOnOpen = true});

  final bool refreshOnOpen;

  @override
  State<HavenHomeScreen> createState() => _HavenHomeScreenState();
}

class _HavenHomeScreenState extends State<HavenHomeScreen> {
  static const _screens = [
    MapScreen(),
    NewspaperScreen(),
    ChatScreen(),
    SettingsScreen(),
  ];

  static const _titles = ['Map', 'Newspaper', 'Agent', 'Settings'];

  @override
  void initState() {
    super.initState();
    if (widget.refreshOnOpen) {
      unawaited(_refreshOnOpen());
    }
  }

  Future<void> _refreshOnOpen() async {
    try {
      await RefreshService().refreshAll();
    } catch (_) {
      // Cached offline content remains visible if startup refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NavigationService.instance.tabIndex,
      builder: (context, index, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          // Don't shrink the body when the soft keyboard opens — that's what
          // was lifting the floating tab bar above the keyboard. The chat
          // composer pads itself with MediaQuery.viewInsets.bottom so the
          // input still floats above the keyboard; tabs stay pinned at the
          // real screen bottom (hidden behind the keyboard while typing).
          resizeToAvoidBottomInset: false,
          body: GlassScaffold(
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Positioned.fill(
                    // Map tab renders edge-to-edge under the floating header
                    // and tab bar; other tabs keep the boxed padding.
                    child: index == HavenTabs.map
                        ? IndexedStack(index: index, children: _screens)
                        : Padding(
                            padding:
                                const EdgeInsets.fromLTRB(18, 84, 18, 104),
                            child:
                                IndexedStack(index: index, children: _screens),
                          ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 10,
                    child: _GlassHeader(title: _titles[index]),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 26,
                    child: _FloatingTabBar(
                      selectedIndex: index,
                      onSelected: (i) =>
                          NavigationService.instance.tabIndex.value = i,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassHeader extends StatelessWidget {
  const _GlassHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      borderRadius: 28,
      opacity: 0.16,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  GlassColors.emergency.withValues(alpha: 0.95),
                  GlassColors.emergency.withValues(alpha: 0.38),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.medical_services, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HAVEN',
                  style: TextStyle(
                    color: GlassColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: GlassColors.safe,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (Icons.map_outlined, Icons.map, 'Map'),
      (Icons.article_outlined, Icons.article, 'News'),
      (Icons.psychology_outlined, Icons.psychology, 'Agent'),
      (Icons.settings_outlined, Icons.settings, 'Settings'),
    ];

    return GlassPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(7),
      borderRadius: 34,
      opacity: 0.2,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
              child: _TabItem(
                icon: tabs[index].$1,
                selectedIcon: tabs[index].$2,
                label: tabs[index].$3,
                selected: selectedIndex == index,
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          color: selected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              color: selected
                  ? GlassColors.textPrimary
                  : GlassColors.textTertiary,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? GlassColors.textPrimary
                    : GlassColors.textTertiary,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
