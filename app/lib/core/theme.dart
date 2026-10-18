import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// 设计令牌：整体参照「秋秋短剧」的深色玻璃质感，同时提供浅色主题。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.accentDeep,
    required this.glass,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color line;
  final Color text;
  final Color textDim;
  final Color accent;
  final Color accentDeep;
  final Color glass;
  final Color shadow;

  static const dark = AppPalette(
    background: Color(0xFF08080C),
    surface: Color(0xFF141419),
    surfaceHigh: Color(0xFF1E1E26),
    line: Color(0x1FFFFFFF),
    text: Color(0xFFF4F4F7),
    textDim: Color(0xFF8E8E9A),
    accent: Color(0xFFFF4D6D),
    accentDeep: Color(0xFFE0244A),
    glass: Color(0x99101015),
    shadow: Color(0xCC000000),
  );

  static const light = AppPalette(
    background: Color(0xFFF6F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF0F0F5),
    line: Color(0x14000000),
    text: Color(0xFF111114),
    textDim: Color(0xFF6C6C78),
    accent: Color(0xFFF0324F),
    accentDeep: Color(0xFFC81E3A),
    glass: Color(0xCCF6F6FA),
    shadow: Color(0x1A000000),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? dark;
  }

  LinearGradient get accentGradient =>
      LinearGradient(colors: [accent, accentDeep], begin: Alignment.topLeft, end: Alignment.bottomRight);

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? line,
    Color? text,
    Color? textDim,
    Color? accent,
    Color? accentDeep,
    Color? glass,
    Color? shadow,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      line: line ?? this.line,
      text: text ?? this.text,
      textDim: textDim ?? this.textDim,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      glass: glass ?? this.glass,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

class AppRadius {
  static const card = 14.0;
  static const sheet = 22.0;
  static const pill = 999.0;
}

ThemeData buildTheme(AppPalette palette, Brightness brightness) {
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    colorScheme: base.colorScheme.copyWith(
      brightness: brightness,
      primary: palette.accent,
      secondary: palette.accent,
      surface: palette.surface,
      onSurface: palette.text,
      error: const Color(0xFFFF5A5F),
    ),
    extensions: <ThemeExtension<dynamic>>[palette],
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: palette.text, displayColor: palette.text),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    }),
  );
}
