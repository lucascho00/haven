import 'dart:ui';

import 'package:flutter/material.dart';

class GlassColors {
  static const backgroundTop = Color(0xFF101114);
  static const backgroundBottom = Color(0xFF050608);
  static const emergency = Color(0xFFFF453A);
  static const safe = Color(0xFF30D158);
  static const cyan = Color(0xFF64D2FF);
  static const amber = Color(0xFFFFD60A);
  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0xFFC7C7CC);
  static const textTertiary = Color(0xFF8E8E93);
  static const glassFill = Color(0x38FFFFFF);
  static const glassStroke = Color(0x45FFFFFF);
}

class GlassScaffold extends StatelessWidget {
  const GlassScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _GlassBackground()),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GlassBackground extends StatelessWidget {
  const _GlassBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [GlassColors.backgroundTop, GlassColors.backgroundBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: _Glow(color: GlassColors.emergency.withValues(alpha: 0.25)),
          ),
          Positioned(
            bottom: 120,
            left: -120,
            child: _Glow(color: GlassColors.cyan.withValues(alpha: 0.16)),
          ),
          Positioned(
            bottom: -130,
            right: 20,
            child: _Glow(color: GlassColors.safe.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 140, spreadRadius: 40)],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderRadius = 26,
    this.opacity = 0.18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: Colors.white.withValues(alpha: opacity),
              border: Border.all(color: GlassColors.glassStroke),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.label,
    this.icon,
    this.color = GlassColors.cyan,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class GlassSectionHeader extends StatelessWidget {
  const GlassSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: GlassColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: GlassColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color = GlassColors.textPrimary,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 42,
              child: Icon(icon, color: color, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
