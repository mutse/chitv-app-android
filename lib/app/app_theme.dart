import 'package:flutter/material.dart';

@immutable
class ChiTvTheme extends ThemeExtension<ChiTvTheme> {
  const ChiTvTheme({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.backgroundGlow,
    required this.backgroundGlowSecondary,
    required this.cardColor,
    required this.elevatedCardColor,
    required this.surfaceColor,
    required this.surfaceMutedColor,
    required this.strokeColor,
    required this.strongStrokeColor,
    required this.accentColor,
    required this.accentMutedColor,
    required this.shadowColor,
    required this.overlayScrim,
    required this.overlayPanel,
    required this.overlayPanelHeavy,
  });

  final Color backgroundTop;
  final Color backgroundBottom;
  final Color backgroundGlow;
  final Color backgroundGlowSecondary;
  final Color cardColor;
  final Color elevatedCardColor;
  final Color surfaceColor;
  final Color surfaceMutedColor;
  final Color strokeColor;
  final Color strongStrokeColor;
  final Color accentColor;
  final Color accentMutedColor;
  final Color shadowColor;
  final Color overlayScrim;
  final Color overlayPanel;
  final Color overlayPanelHeavy;

  LinearGradient get backgroundGradient => LinearGradient(
    colors: [backgroundTop, backgroundBottom],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const light = ChiTvTheme(
    backgroundTop: Color(0xFFF7F3EE),
    backgroundBottom: Color(0xFFE6EDF6),
    backgroundGlow: Color(0xFFF3DEC7),
    backgroundGlowSecondary: Color(0xFFDCE7F5),
    cardColor: Color(0xFFF8F4EE),
    elevatedCardColor: Color(0xFFFFFBF7),
    surfaceColor: Color(0xFFFFFCF8),
    surfaceMutedColor: Color(0xFFF1ECE5),
    strokeColor: Color(0xFFD8CEC2),
    strongStrokeColor: Color(0xFFBCA998),
    accentColor: Color(0xFFA67546),
    accentMutedColor: Color(0xFFE8D4BC),
    shadowColor: Color(0x1C5A3D22),
    overlayScrim: Color(0xB3000000),
    overlayPanel: Color(0x8A21160D),
    overlayPanelHeavy: Color(0xD118110A),
  );

  static const dark = ChiTvTheme(
    backgroundTop: Color(0xFF111418),
    backgroundBottom: Color(0xFF1A2028),
    backgroundGlow: Color(0xFF3C2D1F),
    backgroundGlowSecondary: Color(0xFF233042),
    cardColor: Color(0xFF191D23),
    elevatedCardColor: Color(0xFF20262D),
    surfaceColor: Color(0xFF171B20),
    surfaceMutedColor: Color(0xFF232932),
    strokeColor: Color(0xFF303843),
    strongStrokeColor: Color(0xFF495464),
    accentColor: Color(0xFFD0A977),
    accentMutedColor: Color(0xFF433221),
    shadowColor: Color(0x4D000000),
    overlayScrim: Color(0xB3000000),
    overlayPanel: Color(0x9E090B0E),
    overlayPanelHeavy: Color(0xDE07080B),
  );

  @override
  ChiTvTheme copyWith({
    Color? backgroundTop,
    Color? backgroundBottom,
    Color? backgroundGlow,
    Color? backgroundGlowSecondary,
    Color? cardColor,
    Color? elevatedCardColor,
    Color? surfaceColor,
    Color? surfaceMutedColor,
    Color? strokeColor,
    Color? strongStrokeColor,
    Color? accentColor,
    Color? accentMutedColor,
    Color? shadowColor,
    Color? overlayScrim,
    Color? overlayPanel,
    Color? overlayPanelHeavy,
  }) {
    return ChiTvTheme(
      backgroundTop: backgroundTop ?? this.backgroundTop,
      backgroundBottom: backgroundBottom ?? this.backgroundBottom,
      backgroundGlow: backgroundGlow ?? this.backgroundGlow,
      backgroundGlowSecondary:
          backgroundGlowSecondary ?? this.backgroundGlowSecondary,
      cardColor: cardColor ?? this.cardColor,
      elevatedCardColor: elevatedCardColor ?? this.elevatedCardColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      surfaceMutedColor: surfaceMutedColor ?? this.surfaceMutedColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strongStrokeColor: strongStrokeColor ?? this.strongStrokeColor,
      accentColor: accentColor ?? this.accentColor,
      accentMutedColor: accentMutedColor ?? this.accentMutedColor,
      shadowColor: shadowColor ?? this.shadowColor,
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
      backgroundGlow: Color.lerp(backgroundGlow, other.backgroundGlow, t)!,
      backgroundGlowSecondary: Color.lerp(
        backgroundGlowSecondary,
        other.backgroundGlowSecondary,
        t,
      )!,
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      elevatedCardColor: Color.lerp(
        elevatedCardColor,
        other.elevatedCardColor,
        t,
      )!,
      surfaceColor: Color.lerp(surfaceColor, other.surfaceColor, t)!,
      surfaceMutedColor: Color.lerp(
        surfaceMutedColor,
        other.surfaceMutedColor,
        t,
      )!,
      strokeColor: Color.lerp(strokeColor, other.strokeColor, t)!,
      strongStrokeColor: Color.lerp(
        strongStrokeColor,
        other.strongStrokeColor,
        t,
      )!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      accentMutedColor: Color.lerp(
        accentMutedColor,
        other.accentMutedColor,
        t,
      )!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
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
  final extra = isDark ? ChiTvTheme.dark : ChiTvTheme.light;
  final primary = extra.accentColor;
  final seedScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
  );
  final scheme = seedScheme.copyWith(
    primary: primary,
    onPrimary: isDark ? const Color(0xFF23170D) : Colors.white,
    primaryContainer: extra.accentMutedColor,
    onPrimaryContainer: isDark
        ? const Color(0xFFF6E8D7)
        : const Color(0xFF5A3B1E),
    secondary: isDark ? const Color(0xFF92A8BF) : const Color(0xFF738BA5),
    onSecondary: Colors.white,
    secondaryContainer: isDark
        ? const Color(0xFF273442)
        : const Color(0xFFDCE6F2),
    tertiary: isDark ? const Color(0xFF90A89D) : const Color(0xFF79948A),
    surface: extra.surfaceColor,
    onSurface: isDark ? const Color(0xFFF4F0EA) : const Color(0xFF241D17),
    surfaceContainerLowest: extra.elevatedCardColor,
    surfaceContainerLow: extra.cardColor,
    surfaceContainer: extra.surfaceMutedColor,
    surfaceContainerHigh: isDark
        ? const Color(0xFF242A32)
        : const Color(0xFFF4EEE7),
    surfaceContainerHighest: isDark
        ? const Color(0xFF2D3641)
        : const Color(0xFFEDE4DA),
    outline: extra.strokeColor,
    outlineVariant: extra.strongStrokeColor.withValues(alpha: 0.6),
    shadow: extra.shadowColor,
    scrim: extra.overlayScrim,
  );
  final baseTextTheme = ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
  ).textTheme;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
    extensions: [extra],
    appBarTheme: AppBarTheme(
      backgroundColor: extra.surfaceColor.withValues(
        alpha: isDark ? 0.8 : 0.74,
      ),
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 62,
      titleSpacing: 20,
      shape: Border(
        bottom: BorderSide(color: extra.strokeColor.withValues(alpha: 0.38)),
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
        backgroundColor: extra.elevatedCardColor.withValues(alpha: 0.82),
        foregroundColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: extra.strokeColor.withValues(alpha: 0.72)),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: extra.cardColor.withValues(alpha: isDark ? 0.94 : 0.96),
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shadowColor: extra.shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: extra.strokeColor.withValues(alpha: 0.72)),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: extra.strokeColor.withValues(alpha: 0.65),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: extra.elevatedCardColor.withValues(alpha: 0.98),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: extra.strokeColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: extra.strokeColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: extra.elevatedCardColor,
      selectedColor: scheme.primaryContainer,
      secondarySelectedColor: scheme.primary,
      side: BorderSide(color: extra.strokeColor),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: extra.elevatedCardColor.withValues(alpha: 0.84),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: extra.strokeColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return extra.elevatedCardColor;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.onSurface;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(color: extra.strokeColor.withValues(alpha: 0.85)),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: extra.elevatedCardColor.withValues(alpha: 0.92),
      indicatorColor: scheme.primaryContainer,
      height: 76,
      elevation: 0,
      shadowColor: extra.shadowColor,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
    popupMenuTheme: PopupMenuThemeData(
      color: extra.elevatedCardColor.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: extra.strokeColor.withValues(alpha: 0.72)),
      ),
      textStyle: TextStyle(color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: extra.cardColor.withValues(alpha: 0.98),
      modalBackgroundColor: extra.cardColor.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: extra.elevatedCardColor.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? const Color(0xFF23262D)
          : const Color(0xFFF8F2EA),
      contentTextStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.onPrimary;
        }
        return scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary;
        }
        return scheme.surfaceContainerHighest;
      }),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    textTheme: baseTextTheme
        .copyWith(
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
          headlineSmall: baseTextTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.4),
          bodySmall: baseTextTheme.bodySmall?.copyWith(height: 1.35),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            left: -40,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      extra.backgroundGlow.withValues(alpha: 0.4),
                      extra.backgroundGlow.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: const SizedBox(width: 320, height: 320),
              ),
            ),
          ),
          Positioned(
            right: -90,
            top: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      extra.backgroundGlowSecondary.withValues(alpha: 0.24),
                      extra.backgroundGlowSecondary.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: const SizedBox(width: 280, height: 280),
              ),
            ),
          ),
          child,
        ],
      ),
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
