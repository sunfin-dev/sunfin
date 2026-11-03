import 'package:flutter/material.dart';

import '../../../sunfin/sunfin_style.dart';

/// Sunfin's look for the server administration area, modelled on the
/// settings pages of the reference design's web app:
/// a flat grey page, grey uppercase section names, the open page in a white
/// pill like the sidebar, settings straight on the page between thin lines,
/// gold buttons.
abstract final class AdminLook {
  static const page = SunfinStyle.background;

  /// Thin lines between settings and along the menu and bar.
  static const line = Color(0xFF33383C);

  /// Fields and anything that sits a step above the page.
  static const raised = Color(0xFF282C30);

  /// Section names and secondary text.
  static const muted = Color(0xFF9A9D9F);

  static const text = Colors.white;
  static const gold = SunfinStyle.accent;
  static const onGold = Color(0xFF1F1F1F);

  /// The open page's pill in the menu.
  static const pill = Colors.white;
  static const onPill = SunfinStyle.background;

  static const radius = 4.0;
  static final borderRadius = BorderRadius.circular(radius);

  static const sectionStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.1,
    color: muted,
  );

  /// [base] with the colours and shapes every admin page builds on, so the
  /// pages' own cards, switches and buttons take the look without changes.
  static ThemeData theme(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: gold,
      onPrimary: onGold,
      primaryContainer: const Color(0xFF3A3121),
      onPrimaryContainer: gold,
      secondaryContainer: raised,
      onSecondaryContainer: text,
      surface: page,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceContainerLowest: page,
      surfaceContainerLow: page,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: const Color(0xFF30353A),
      outline: const Color(0xFF4A4F53),
      outlineVariant: line,
      surfaceTint: Colors.transparent,
    );
    final shape = RoundedRectangleBorder(borderRadius: borderRadius);
    final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(shape);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      dividerColor: line,
      dividerTheme: const DividerThemeData(color: line, space: 1, thickness: 1),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: const BorderSide(color: line),
        ),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: raised,
        shape: shape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: onGold,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: shape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: onGold,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: buttonShape,
          side: const WidgetStatePropertyAll(BorderSide(color: line)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: buttonShape,
          foregroundColor: const WidgetStatePropertyAll(gold),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(shape: buttonShape),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: raised,
        side: const BorderSide(color: line),
        shape: shape,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onGold : muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? gold : raised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.transparent : line,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? gold : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(onGold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      radioTheme: const RadioThemeData(fillColor: WidgetStatePropertyAll(gold)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: gold,
        linearTrackColor: raised,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: gold,
        thumbColor: gold,
        inactiveTrackColor: raised,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: const BorderSide(color: gold, width: 1.5),
        ),
        floatingLabelStyle: const TextStyle(color: gold),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        iconColor: muted,
        shape: shape,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        indicatorColor: gold,
        labelColor: text,
        unselectedLabelColor: muted,
        dividerColor: line,
      ),
      drawerTheme: base.drawerTheme.copyWith(
        backgroundColor: page,
        shape: const RoundedRectangleBorder(),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: raised,
        contentTextStyle: const TextStyle(color: text),
        shape: shape,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(color: raised, shape: shape),
    );
  }
}
