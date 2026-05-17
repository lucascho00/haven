import 'package:flutter/material.dart';

import '../models/manual_item.dart';
import '../services/local_agent_service.dart';
import '../services/news_service.dart';
import '../storage/haven_cache.dart';
import '../ui/glass_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    LocalAgentService.instance.addListener(_onAgentChange);
  }

  @override
  void dispose() {
    LocalAgentService.instance.removeListener(_onAgentChange);
    super.dispose();
  }

  void _onAgentChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final manuals = HavenCache.getManuals();
    final lastRefresh = HavenCache.getLastRefresh();
    final agent = LocalAgentService.instance;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        GlassPanel(
          opacity: 0.2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings & Manuals',
                style: TextStyle(
                  color: GlassColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                lastRefresh == null
                    ? 'Cache has not been refreshed yet.'
                    : 'Last refresh ${_formatDate(lastRefresh)}',
                style: const TextStyle(color: GlassColors.textSecondary),
              ),
            ],
          ),
        ),
        const GlassSectionHeader(
          title: 'Local Agent Backend',
          subtitle:
              'LiteRT-LM accelerator. GPU is fastest on real iPhones; CPU is the only option on the iOS Simulator.',
        ),
        _BackendChoiceCard(
          current: agent.backendChoice,
          onChanged: (choice) async {
            await agent.setBackendChoice(choice);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Backend set to ${choice.displayName}. Open the Agent tab and tap reset for the change to take effect.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        const GlassSectionHeader(
          title: 'Survival Manuals',
          subtitle: 'Step-by-step guidance designed to be readable under stress',
        ),
        if (manuals.isEmpty)
          const _EmptyCard(text: 'Manuals are being prepared.')
        else
          ...manuals.map(_ManualCard.new),
        const GlassSectionHeader(
          title: 'Fetch Sources',
          subtitle: 'Enabled sources update the offline newspaper cache',
        ),
        ...NewsService.sourceOptions.map(_SourceOptionCard.new),
        const SizedBox(height: 16),
        const _LiteRtFooter(),
      ],
    );
  }

  String _formatDate(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}

class _LiteRtFooter extends StatelessWidget {
  const _LiteRtFooter();

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 20,
      opacity: 0.1,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 14,
                color: GlassColors.safe.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                'POWERED BY GOOGLE AI EDGE',
                style: TextStyle(
                  color: GlassColors.safe.withValues(alpha: 0.95),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'On-device inference runs Gemma 4 E2B (LiteRT-LM, .litertlm) '
            'through Google AI Edge\'s LiteRT-LM SDK with Metal / OpenCL '
            'acceleration. Native function calling is routed through the SDK\'s '
            'tools_json mechanism. No prompts, no responses, and no cached '
            'context ever leave the device.',
            style: TextStyle(
              color: GlassColors.textSecondary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackendChoiceCard extends StatelessWidget {
  const _BackendChoiceCard({required this.current, required this.onChanged});

  final BackendChoice current;
  final ValueChanged<BackendChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      opacity: 0.16,
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          for (final choice in BackendChoice.values)
            _BackendOption(
              choice: choice,
              selected: choice == current,
              onTap: () => onChanged(choice),
            ),
        ],
      ),
    );
  }
}

class _BackendOption extends StatelessWidget {
  const _BackendOption({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final BackendChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? GlassColors.emergency.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: selected
                ? GlassColors.emergency.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? GlassColors.emergency : GlassColors.textTertiary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                choice.displayName,
                style: TextStyle(
                  color: selected ? GlassColors.textPrimary : GlassColors.textSecondary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 22,
      opacity: 0.12,
      child: Text(text, style: const TextStyle(color: GlassColors.textSecondary)),
    );
  }
}
