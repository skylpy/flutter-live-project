import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首期支持的四套主题。
enum AppThemeId { starryPurple, sweetPink, freshBlue, naturalGreen }

/// 语义化设计令牌，保证换肤时背景、卡片、文字和状态色同步变化。
@immutable
class LiveThemeExtension extends ThemeExtension<LiveThemeExtension> {
  const LiveThemeExtension({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.primary,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.live,
    required this.success,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color primary;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final Color live;
  final Color success;
  final Color danger;

  @override
  LiveThemeExtension copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? primary,
    Color? secondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? divider,
    Color? live,
    Color? success,
    Color? danger,
  }) => LiveThemeExtension(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    divider: divider ?? this.divider,
    live: live ?? this.live,
    success: success ?? this.success,
    danger: danger ?? this.danger,
  );

  @override
  LiveThemeExtension lerp(
    covariant ThemeExtension<LiveThemeExtension>? other,
    double t,
  ) {
    if (other is! LiveThemeExtension) return this;
    return LiveThemeExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      live: Color.lerp(live, other.live, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const _background = Color(0xFF0D0F1C);
  static const _surface = Color(0xFF171A2A);
  static const _surfaceVariant = Color(0xFF22253A);
  static const _secondaryText = Color(0xFFA9AEC1);
  static const _divider = Color(0xFF2A2D40);

  static ThemeData data(AppThemeId id) {
    final tokens = _tokens(id);
    final scheme = ColorScheme.fromSeed(
      seedColor: tokens.primary,
      brightness: Brightness.dark,
      surface: tokens.surface,
      surfaceContainerHighest: tokens.surfaceVariant,
      primary: tokens.primary,
      secondary: tokens.secondary,
      error: tokens.danger,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.background,
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surface.withValues(alpha: 0.96),
        indicatorColor: tokens.primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: tokens.textSecondary),
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceVariant,
        hintStyle: TextStyle(color: tokens.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.primary),
        ),
      ),
      dividerTheme: DividerThemeData(color: tokens.divider),
    );
  }

  static LiveThemeExtension _tokens(AppThemeId id) {
    final colors = switch (id) {
      AppThemeId.starryPurple => (
        primary: const Color(0xFFE84DDB),
        secondary: const Color(0xFF8E5CF6),
      ),
      AppThemeId.sweetPink => (
        primary: const Color(0xFFFF6FAE),
        secondary: const Color(0xFFFF9BCA),
      ),
      AppThemeId.freshBlue => (
        primary: const Color(0xFF58A6FF),
        secondary: const Color(0xFF7CD8FF),
      ),
      AppThemeId.naturalGreen => (
        primary: const Color(0xFF65C18C),
        secondary: const Color(0xFFB4E197),
      ),
    };
    return LiveThemeExtension(
      background: _background,
      surface: _surface,
      surfaceVariant: _surfaceVariant,
      primary: colors.primary,
      secondary: colors.secondary,
      textPrimary: Colors.white,
      textSecondary: _secondaryText,
      divider: _divider,
      live: const Color(0xFFFF5F75),
      success: const Color(0xFF54D38A),
      danger: const Color(0xFFFF647C),
    );
  }

  static LiveThemeExtension tokens(BuildContext context) =>
      Theme.of(context).extension<LiveThemeExtension>()!;

  static AppThemeId? parse(String? value) => AppThemeId.values
      .cast<AppThemeId?>()
      .firstWhere((id) => id?.name == value, orElse: () => null);
}

final appThemeProvider = NotifierProvider<AppThemeController, AppThemeId>(
  AppThemeController.new,
);

/// 异步恢复主题，选择后立即更新并写入本地偏好。
class AppThemeController extends Notifier<AppThemeId> {
  static const _storageKey = 'app_theme_id';

  @override
  AppThemeId build() {
    unawaited(_restore());
    return AppThemeId.starryPurple;
  }

  Future<void> select(AppThemeId id) async {
    state = id;
    await (await SharedPreferences.getInstance()).setString(
      _storageKey,
      id.name,
    );
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = AppTheme.parse(preferences.getString(_storageKey));
    if (saved != null) state = saved;
  }
}
