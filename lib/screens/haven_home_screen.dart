import 'package:flutter/material.dart';

import '../services/news_service.dart';
import '../ui/glass_theme.dart';
import 'chat_screen.dart';
import 'manuals_screen.dart';
import 'newspaper_screen.dart';

class HavenHomeScreen extends StatefulWidget {
  const HavenHomeScreen({super.key});

  @override
  State<HavenHomeScreen> createState() => _HavenHomeScreenState();
}

class _HavenHomeScreenState extends State<HavenHomeScreen> {
  int _index = 0;

  static const _screens = [ManualsScreen(), NewspaperScreen(), ChatScreen()];

  static const _titles = ['Manuals', 'Newspaper', 'Local AI'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassScaffold(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 84, 18, 104),
                  child: IndexedStack(index: _index, children: _screens),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                top: 10,
                child: _GlassHeader(
                  title: _titles[_index],
                  onSettingsTap: () => _showSettings(context),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 26,
                child: _FloatingTabBar(
                  selectedIndex: _index,
                  onSelected: (index) => setState(() => _index = index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => const _SettingsSheet(),
    );
  }
}

class _GlassHeader extends StatelessWidget {
  const _GlassHeader({required this.title, required this.onSettingsTap});

  final String title;
  final VoidCallback onSettingsTap;

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
            child: const Icon(Icons.shield_outlined, color: Colors.white),
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
          GlassIconButton(
            icon: Icons.settings_outlined,
            onPressed: onSettingsTap,
            color: GlassColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: GlassPanel(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            borderRadius: 34,
            opacity: 0.22,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
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
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: GlassColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Newspaper fetch sources and offline cache configuration.',
                  style: TextStyle(
                    color: GlassColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const GlassSectionHeader(
                  title: 'Fetch Sources',
                  subtitle:
                      'Enabled sources update the offline newspaper cache',
                ),
                ...NewsService.sourceOptions.map(_SourceOptionCard.new),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SourceOptionCard extends StatelessWidget {
  const _SourceOptionCard(this.source);

  final NewsSourceOption source;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      opacity: source.enabled ? 0.14 : 0.09,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            source.enabled ? Icons.check_circle : Icons.radio_button_unchecked,
            color: source.enabled ? GlassColors.safe : GlassColors.textTertiary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        source.name,
                        style: const TextStyle(
                          color: GlassColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    GlassPill(
                      label: source.enabled ? 'ON' : 'PLANNED',
                      color: source.enabled
                          ? GlassColors.safe
                          : GlassColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  source.description,
                  style: const TextStyle(
                    color: GlassColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  source.endpoint,
                  style: const TextStyle(
                    color: GlassColors.textTertiary,
                    fontSize: 11,
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
      (Icons.health_and_safety_outlined, Icons.health_and_safety, 'Manuals'),
      (Icons.article_outlined, Icons.article, 'News'),
      (Icons.psychology_outlined, Icons.psychology, 'AI'),
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
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
