import 'package:flutter/material.dart';

import '../models/manual_item.dart';
import '../models/safe_place.dart';
import '../services/refresh_service.dart';
import '../storage/haven_cache.dart';
import '../ui/glass_theme.dart';

class ManualsScreen extends StatefulWidget {
  const ManualsScreen({super.key});

  @override
  State<ManualsScreen> createState() => _ManualsScreenState();
}

class _ManualsScreenState extends State<ManualsScreen> {
  bool _refreshing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    if (HavenCache.getManuals().isEmpty) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _status = null;
    });

    try {
      final result = await RefreshService().refreshAll();
      if (!mounted) return;
      setState(() {
        _status = result.location == null
            ? 'Location unavailable. Showing general offline manuals.'
            : 'Updated for ${result.location!.label}. '
                  '${result.safePlaceCount} safe places cached.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not refresh. Showing cached offline content.';
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manuals = HavenCache.getManuals();
    final places = HavenCache.getSafePlaces();
    final location = HavenCache.getLastLocation();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _HeaderCard(
            title: 'Manuals for ${location?.label ?? 'your area'}',
            subtitle:
                'Offline survival steps, nearby safe places, and cached route estimates.',
            action: _refreshing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
          ),
          if (_status != null) _InfoText(_status!),
          GlassSectionHeader(
            title: 'Safe Places',
            subtitle: 'Cached fastest routes when online data is available',
          ),
          if (places.isEmpty)
            const _EmptyCard(
              text:
                  'No safe places cached yet. Connect to the internet and refresh after allowing GPS.',
            )
          else
            ...places.map(_SafePlaceCard.new),
          const GlassSectionHeader(
            title: 'Direct Manuals',
            subtitle: 'Steps designed to be readable under stress',
          ),
          if (manuals.isEmpty)
            const _EmptyCard(text: 'Manuals are being prepared.')
          else
            ...manuals.map(_ManualCard.new),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      opacity: 0.2,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: GlassColors.textSecondary),
                  ),
                ],
              ),
            ),
            action,
          ],
        ),
      ),
    );
  }
}

class _SafePlaceCard extends StatelessWidget {
  const _SafePlaceCard(this.place);

  final SafePlace place;

  @override
  Widget build(BuildContext context) {
    final route = place.routeDurationSeconds == null
        ? 'Route not cached'
        : '${(place.routeDurationSeconds! / 60).round()} min fastest route';
    final distance = place.routeDistanceMeters ?? place.distanceMeters;

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      borderRadius: 22,
      opacity: 0.14,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: GlassColors.safe.withValues(alpha: 0.14),
              border: Border.all(
                color: GlassColors.safe.withValues(alpha: 0.28),
              ),
            ),
            child: const Icon(Icons.place, color: GlassColors.safe),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    color: GlassColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    GlassPill(label: place.type, color: GlassColors.safe),
                    GlassPill(label: route, icon: Icons.route_outlined),
                    if (distance != null)
                      GlassPill(
                        label: '${(distance / 1000).toStringAsFixed(1)} km',
                        icon: Icons.near_me_outlined,
                        color: GlassColors.textSecondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualCard extends StatelessWidget {
  const _ManualCard(this.manual);

  final ManualItem manual;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderRadius: 24,
      opacity: 0.14,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: GlassColors.textPrimary,
          collapsedIconColor: GlassColors.textSecondary,
          title: Text(
            manual.title,
            style: const TextStyle(
              color: GlassColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassPill(
                  label: manual.category,
                  color: manual.category == 'Medical'
                      ? GlassColors.emergency
                      : GlassColors.cyan,
                ),
                const SizedBox(height: 8),
                Text(
                  manual.summary,
                  style: const TextStyle(color: GlassColors.textSecondary),
                ),
              ],
            ),
          ),
          children: [
            for (var i = 0; i < manual.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: GlassColors.emergency.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        manual.steps[i],
                        style: const TextStyle(
                          color: GlassColors.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      opacity: 0.12,
      child: Text(
        text,
        style: const TextStyle(color: GlassColors.textSecondary),
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: const TextStyle(color: GlassColors.safe, fontSize: 12),
      ),
    );
  }
}
