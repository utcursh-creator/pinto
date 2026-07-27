import 'package:flutter/material.dart';

import '../theme/brand_tokens.dart';

/// A small primitives layer modelled on shadcn/ui's COMPOSITION discipline -
/// semantic tokens plus a handful of named states - translated to Flutter.
/// (shadcn itself is React + Tailwind and cannot run here; what ports is the
/// method: name the semantic roles once, then build every screen out of the
/// same few pieces so empty/loading/error states cannot drift per screen.)

/// Semantic colour roles, resolved per platform/brightness, exposed as a
/// ThemeExtension so screens stop hardcoding Color(0xFF...) literals.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.destructive,
    required this.destructiveSurface,
    required this.warning,
    required this.warningSurface,
    required this.accent,
    required this.accentSurface,
  });

  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color destructive;
  final Color destructiveSurface;
  final Color warning;
  final Color warningSurface;
  final Color accent;
  final Color accentSurface;

  static const light = AppSemanticColors(
    muted: Color(0xFFF4F5F4),
    mutedForeground: Color(0xFF6B6F6D),
    border: Color(0xFFE2E4E3),
    destructive: Color(0xFFB3261E),
    destructiveSurface: Color(0xFFFFE5E2),
    warning: Color(0xFF8A6D00),
    warningSurface: Color(0xFFFFF3CD),
    accent: BrandTokens.teal,
    accentSurface: BrandTokens.tealLight,
  );

  static const dark = AppSemanticColors(
    muted: Color(0xFF1D211F),
    mutedForeground: Color(0xFF9BA19E),
    border: Color(0xFF2C312F),
    destructive: Color(0xFFF2B8B5),
    destructiveSurface: Color(0xFF3A1512),
    warning: Color(0xFFF5D67B),
    warningSurface: Color(0xFF3A2F00),
    accent: Color(0xFF57C7A5),
    accentSurface: Color(0xFF10352B),
  );

  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  AppSemanticColors copyWith({
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? destructive,
    Color? destructiveSurface,
    Color? warning,
    Color? warningSurface,
    Color? accent,
    Color? accentSurface,
  }) =>
      AppSemanticColors(
        muted: muted ?? this.muted,
        mutedForeground: mutedForeground ?? this.mutedForeground,
        border: border ?? this.border,
        destructive: destructive ?? this.destructive,
        destructiveSurface: destructiveSurface ?? this.destructiveSurface,
        warning: warning ?? this.warning,
        warningSurface: warningSurface ?? this.warningSurface,
        accent: accent ?? this.accent,
        accentSurface: accentSurface ?? this.accentSurface,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemanticColors(
      muted: c(muted, other.muted),
      mutedForeground: c(mutedForeground, other.mutedForeground),
      border: c(border, other.border),
      destructive: c(destructive, other.destructive),
      destructiveSurface: c(destructiveSurface, other.destructiveSurface),
      warning: c(warning, other.warning),
      warningSurface: c(warningSurface, other.warningSurface),
      accent: c(accent, other.accent),
      accentSurface: c(accentSurface, other.accentSurface),
    );
  }
}

/// shadcn `Skeleton`: a shaped placeholder, so a loading list looks like the
/// list it is about to become instead of a lone centred spinner.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    this.width,
    this.height = 14,
    this.radius = 6,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemanticColors.of(context);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: s.muted,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A skeleton shaped like a list of rows - the default loading state for any
/// list screen.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({this.rows = 5, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows,
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AppSkeleton(width: 40, height: 40, radius: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(height: 12),
                  SizedBox(height: 8),
                  AppSkeleton(width: 140, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// shadcn `Empty`: an icon, a line that says why it is empty, and - crucially -
/// the action that fills it. The review found empty states with no next action,
/// which read as dead ends.
class AppEmpty extends StatelessWidget {
  const AppEmpty({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = AppSemanticColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: s.mutedForeground),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: s.mutedForeground),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

enum AppAlertTone { info, warning, destructive }

/// shadcn `Alert`: an inline, non-blocking statement of fact. Used for the
/// states that are not errors but must not be silent (free hit, innings break,
/// orphaned deliveries, an expired invite).
class AppAlert extends StatelessWidget {
  const AppAlert({
    required this.message,
    this.tone = AppAlertTone.info,
    this.icon,
    this.action,
    super.key,
  });

  final String message;
  final AppAlertTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = AppSemanticColors.of(context);
    final (bg, fg) = switch (tone) {
      AppAlertTone.info => (s.accentSurface, s.accent),
      AppAlertTone.warning => (s.warningSurface, s.warning),
      AppAlertTone.destructive => (s.destructiveSurface, s.destructive),
    };
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Icon(icon ?? Icons.info_outline, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// shadcn `Field` / `FieldGroup`: one label + control + help/error shape, so
/// forms stop inventing their own per screen.
class AppField extends StatelessWidget {
  const AppField({
    required this.label,
    required this.child,
    this.help,
    this.error,
    super.key,
  });

  final String label;
  final Widget child;
  final String? help;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          child,
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error!,
                style: TextStyle(color: s.destructive, fontSize: 12)),
          ] else if (help != null) ...[
            const SizedBox(height: 4),
            Text(help!,
                style: TextStyle(color: s.mutedForeground, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class AppFieldGroup extends StatelessWidget {
  const AppFieldGroup({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = AppSemanticColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!,
                style: TextStyle(
                    color: s.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
            const SizedBox(height: 4),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// shadcn `ToggleGroup`: a single-select set of options. Replaces the ad-hoc
/// ChoiceChip rows that each screen was rebuilding by hand.
class AppToggleGroup<T> extends StatelessWidget {
  const AppToggleGroup({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: value == v,
            onSelected: (_) => onChanged(v),
          ),
      ],
    );
  }
}
