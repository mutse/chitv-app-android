import 'package:flutter/material.dart';

@immutable
class ChiTvTheme extends ThemeExtension<ChiTvTheme> {
  const ChiTvTheme({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.cardColor,
    required this.surfaceColor,
    required this.strokeColor,
    required this.overlayScrim,
    required this.overlayPanel,
    required this.overlayPanelHeavy,
  });

  final Color backgroundTop;
  final Color backgroundBottom;
  final Color cardColor;
  final Color surfaceColor;
  final Color strokeColor;
  final Color overlayScrim;
  final Color overlayPanel;
  final Color overlayPanelHeavy;

  LinearGradient get backgroundGradient => LinearGradient(
    colors: [backgroundTop, backgroundBottom],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const light = ChiTvTheme(
    backgroundTop: Color(0xFFF2F5FA),
    backgroundBottom: Color(0xFFDDE7F7),
    cardColor: Color(0xFFF2F7FF),
    surfaceColor: Color(0xFFFCFDFF),
    strokeColor: Color(0xFFC2D1E5),
    overlayScrim: Color(0xB3000000),
    overlayPanel: Color(0x8C000000),
    overlayPanelHeavy: Color(0xD1000000),
  );

  static const dark = ChiTvTheme(
    backgroundTop: Color(0xFF0D1117),
    backgroundBottom: Color(0xFF141B25),
    cardColor: Color(0xFF1B2431),
    surfaceColor: Color(0xFF151D28),
    strokeColor: Color(0xFF2B3544),
    overlayScrim: Color(0xB3000000),
    overlayPanel: Color(0x8C000000),
    overlayPanelHeavy: Color(0xD1000000),
  );

  @override
  ChiTvTheme copyWith({
    Color? backgroundTop,
    Color? backgroundBottom,
    Color? cardColor,
    Color? surfaceColor,
    Color? strokeColor,
    Color? overlayScrim,
    Color? overlayPanel,
    Color? overlayPanelHeavy,
  }) {
    return ChiTvTheme(
      backgroundTop: backgroundTop ?? this.backgroundTop,
      backgroundBottom: backgroundBottom ?? this.backgroundBottom,
      cardColor: cardColor ?? this.cardColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      strokeColor: strokeColor ?? this.strokeColor,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      overlayPanel: overlayPanel ?? this.overlayPanel,
      overlayPanelHeavy: overlayPanelHeavy ?? this.overlayPanelHeavy,
    );
  }

  @override
  ThemeExtension<ChiTvTheme> lerp(ThemeExtension<ChiTvTheme>? other, double t) {
    if (other is! ChiTvTheme) {
      return this;
    }

    return ChiTvTheme(
      backgroundTop: Color.lerp(backgroundTop, other.backgroundTop, t)!,
      backgroundBottom: Color.lerp(
        backgroundBottom,
        other.backgroundBottom,
        t,
      )!,
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      surfaceColor: Color.lerp(surfaceColor, other.surfaceColor, t)!,
      strokeColor: Color.lerp(strokeColor, other.strokeColor, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
      overlayPanel: Color.lerp(overlayPanel, other.overlayPanel, t)!,
      overlayPanelHeavy: Color.lerp(
        overlayPanelHeavy,
        other.overlayPanelHeavy,
        t,
      )!,
    );
  }
}

extension ChiTvThemeContext on BuildContext {
  ChiTvTheme get chitvTheme => Theme.of(this).extension<ChiTvTheme>()!;
}

ThemeData buildChiTvTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  const primary = Color(0xFF4EA7FF);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        secondary: const Color(0xFF79B7FF),
        tertiary: const Color(0xFF8AD8C9),
        surface: isDark ? const Color(0xFF151D28) : const Color(0xFFFCFDFF),
        surfaceContainerHighest: isDark
            ? const Color(0xFF212B39)
            : const Color(0xFFE6EEF8),
        outlineVariant: isDark
            ? const Color(0xFF324052)
            : const Color(0xFFC8D4E3),
      );
  final extra = isDark ? ChiTvTheme.dark : ChiTvTheme.light;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    extensions: [extra],
    appBarTheme: AppBarTheme(
      backgroundColor: extra.surfaceColor.withValues(alpha: 0.72),
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 62,
      titleSpacing: 20,
      shape: Border(
        bottom: BorderSide(color: extra.strokeColor.withValues(alpha: 0.4)),
      ),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: extra.surfaceColor.withValues(alpha: 0.9),
        foregroundColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: extra.strokeColor.withValues(alpha: 0.75)),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: extra.cardColor.withValues(alpha: 0.94),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: extra.strokeColor.withValues(alpha: 0.8)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: extra.strokeColor.withValues(alpha: 0.65),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: extra.surfaceColor.withValues(alpha: 0.96),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: extra.strokeColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: extra.strokeColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: extra.surfaceColor,
      selectedColor: scheme.primary,
      secondarySelectedColor: scheme.primary,
      side: BorderSide(color: extra.strokeColor),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: extra.surfaceColor.withValues(alpha: 0.9),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: extra.strokeColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: extra.surfaceColor.withValues(alpha: 0.92),
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    textTheme:
        ThemeData(
          colorScheme: scheme,
          brightness: brightness,
          useMaterial3: true,
        ).textTheme.apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        ),
  );
}

class ChiTvBackground extends StatelessWidget {
  const ChiTvBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final extra = context.chitvTheme;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: extra.backgroundGradient),
      child: child,
    );
  }
}

class ChiTvNavTitle extends StatelessWidget {
  const ChiTvNavTitle({super.key, required this.title, this.eyebrow});

  final String? eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasEyebrow = eyebrow != null && eyebrow!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasEyebrow) ...[
          Text(
            eyebrow!,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 1),
        ],
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class ChiTvLargeNavHeader extends StatelessWidget {
  const ChiTvLargeNavHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.progress = 1,
  });

  final String title;
  final String? subtitle;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = progress.clamp(0.0, 1.0);
    final titleScale = 0.95 + (0.05 * clamped);
    final translateY = 10 * (1 - clamped);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    return Transform.translate(
      offset: Offset(0, translateY),
      child: Opacity(
        opacity: clamped,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (hasSubtitle) ...[
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Transform.scale(
                alignment: Alignment.centerLeft,
                scale: titleScale,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (!hasSubtitle) const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}
