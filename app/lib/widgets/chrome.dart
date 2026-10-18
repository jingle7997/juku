import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 毛玻璃容器：底栏、悬浮头图都基于它。
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.blur = 22,
    this.color,
    this.borderRadius,
    this.border,
    this.padding,
  });

  final Widget child;
  final double blur;
  final Color? color;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? palette.glass,
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing, this.padding});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 22, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 15,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: palette.accent, borderRadius: BorderRadius.circular(2)),
                    ),
                    Text(
                      title,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: palette.text, letterSpacing: -0.2),
                    ),
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 11, top: 3),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12, color: palette.textDim)),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 底部导航用的小图标 + 文字
class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = selected ? palette.accent : palette.textDim;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? activeIcon : icon, size: 23, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10, height: 1.1, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: palette.surfaceHigh, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: palette.textDim),
            ),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.text)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: palette.textDim),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.loading = false, this.expand = true});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
          )
        else if (icon != null)
          Icon(icon, size: 18, color: Colors.white),
        if (loading || icon != null) const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            height: 46,
            width: expand ? double.infinity : null,
            padding: expand ? null : const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: palette.accentGradient, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: palette.line),
            color: palette.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 17, color: palette.text), const SizedBox(width: 7)],
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingGrid extends StatelessWidget {
  const LoadingGrid({super.key, this.count = 9, this.aspect = 3 / 4});
  final int count;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.58,
      ),
      itemCount: count,
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.card)),
            ),
          ),
          const SizedBox(height: 7),
          Container(height: 10, width: 70, decoration: BoxDecoration(color: palette.surfaceHigh, borderRadius: BorderRadius.circular(3))),
        ],
      ),
    );
  }
}
