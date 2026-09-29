import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/delivery.dart';

/// Design system for the app: a premium dark canvas lit by an electric-lime
/// brand with a luminous aqua accent for everything AI.
///
/// Screens should pull colours from these tokens instead of hard-coding them,
/// so the whole product stays consistent and can be re-skinned from here.
class AppTheme {
  AppTheme._();

  // ------------------------------------------------------------------ canvas
  /// Deep charcoal-navy background.
  static const Color bg = Color(0xFF0A0E13);

  /// Card surface - one step lighter than the canvas.
  static const Color surface = Color(0xFF121A23);

  /// Nested surface: inputs, note blocks, inner tiles.
  static const Color surfaceAlt = Color(0xFF18222D);

  /// Raised surface: dialogs, snackbars, chips.
  static const Color surfaceHigh = Color(0xFF1F2B38);

  /// Hairline separators and card borders.
  static const Color hairline = Color(0xFF26333F);

  // -------------------------------------------------------------------- text
  static const Color ink = Color(0xFFEDF2F7);
  static const Color inkMuted = Color(0xFF94A2B3);
  static const Color inkFaint = Color(0xFF64748B);

  // ------------------------------------------------------------------ brand
  /// Electric lime: the signature colour of the brand.
  static const Color brand = Color(0xFFB4FF39);

  /// Deeper lime, used for tinted fills and lime-on-lime details.
  static const Color brandDark = Color(0xFF79C93B);

  /// Foreground for primary buttons sitting on lime.
  static const Color onBrand = Color(0xFF0B1405);

  /// Luminous aqua: the "AI is talking" accent.
  static const Color accent = Color(0xFF5FE3C0);

  // --------------------------------------------------------------- semantic
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFFB020);
  static const Color danger = Color(0xFFFF6B6B);

  // -------------------------------------------------------------- gradients
  /// Signature gradient (lime -> aqua) for brand moments.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brand, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle background wash used behind hero areas.
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF16241A), Color(0xFF0E1620)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Radial lime bloom, layered behind heroes and key callouts.
  static RadialGradient bloom({double alpha = 0.28}) => RadialGradient(
        center: Alignment.topRight,
        radius: 1.15,
        colors: [brand.withValues(alpha: alpha), Colors.transparent],
      );

  // --------------------------------------------------------------- elevation
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ];

  /// The one card treatment used across the app.
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hairline),
        boxShadow: cardShadow,
      );

  /// Softer variant for tiles nested inside a card.
  static BoxDecoration get innerDecoration => BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      );

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: brand,
      onPrimary: onBrand,
      primaryContainer: Color(0xFF2A3D17),
      onPrimaryContainer: brand,
      secondary: accent,
      onSecondary: Color(0xFF062019),
      secondaryContainer: Color(0xFF12312A),
      onSecondaryContainer: accent,
      tertiary: warning,
      onTertiary: Color(0xFF251800),
      error: danger,
      onError: Color(0xFF2A0707),
      errorContainer: Color(0xFF3A1414),
      onErrorContainer: Color(0xFFFFB4B4),
      surface: bg,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      surfaceContainerHighest: surfaceHigh,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      outline: hairline,
      outlineVariant: hairline,
      shadow: Colors.black,
      inverseSurface: ink,
      onInverseSurface: bg,
      inversePrimary: Color(0xFF3E6B1B),
      scrim: Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),

      textTheme: const TextTheme(
        displaySmall: TextStyle(
            fontSize: 30, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.8, height: 1.1),
        headlineSmall: TextStyle(
            fontSize: 24, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.5, height: 1.2),
        titleLarge: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.5, height: 1.2),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.2),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
        bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14.5, color: Color(0xFFC4CFDB), height: 1.4),
        bodySmall: TextStyle(fontSize: 12.5, color: inkMuted, height: 1.35),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.1),
        labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: inkMuted),
        labelSmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: inkFaint),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: const TextStyle(color: inkFaint, fontSize: 14.5),
        labelStyle: const TextStyle(color: inkMuted, fontSize: 14.5),
        floatingLabelStyle: const TextStyle(color: brand, fontWeight: FontWeight.w700),
        prefixIconColor: inkMuted,
        suffixIconColor: inkMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: danger, width: 1.6),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: onBrand,
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: inkFaint,
          shadowColor: brand.withValues(alpha: 0.45),
          elevation: 6,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: -0.1),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          disabledForegroundColor: inkFaint,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: hairline),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: inkMuted),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D131A),
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: brand.withValues(alpha: 0.16),
        height: 72,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? brand : inkMuted,
            size: 23,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        side: const BorderSide(color: hairline),
        backgroundColor: surfaceAlt,
        selectedColor: brand.withValues(alpha: 0.16),
        checkmarkColor: brand,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),

      dividerTheme: const DividerThemeData(color: hairline, space: 1, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        elevation: 8,
        contentTextStyle: const TextStyle(color: ink, fontSize: 14, height: 1.35),
        actionTextColor: brand,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: hairline),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: hairline),
        ),
        titleTextStyle: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.3),
        contentTextStyle: const TextStyle(fontSize: 14.5, color: inkMuted, height: 1.4),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: surfaceHigh,
        circularTrackColor: surfaceHigh,
        refreshBackgroundColor: surfaceHigh,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: inkMuted,
        textColor: ink,
        contentPadding: EdgeInsets.zero,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onBrand : inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : surfaceHigh,
        ),
        trackOutlineColor: WidgetStatePropertyAll(hairline),
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: brand,
        textColor: onBrand,
        smallSize: 9,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHigh,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: hairline),
        ),
        textStyle: const TextStyle(fontSize: 14, color: ink),
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(inkFaint.withValues(alpha: 0.5)),
        radius: const Radius.circular(8),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}

extension DeliveryStatusStyle on DeliveryStatus {
  /// Bright on the dark canvas so status reads at a glance while driving.
  Color get color => switch (this) {
        DeliveryStatus.pending => const Color(0xFF98A6B8),
        DeliveryStatus.inTransit => const Color(0xFFFFB020),
        DeliveryStatus.failed => const Color(0xFFFF6B6B),
        DeliveryStatus.delivered => const Color(0xFF4ADE80),
      };

  Color get background => color.withValues(alpha: 0.15);

  IconData get icon => switch (this) {
        DeliveryStatus.pending => Icons.schedule,
        DeliveryStatus.inTransit => Icons.local_shipping_outlined,
        DeliveryStatus.failed => Icons.error_outline,
        DeliveryStatus.delivered => Icons.check_circle_outline,
      };
}

extension ChannelStyle on MessageChannel {
  IconData get icon => switch (this) {
        MessageChannel.sms => Icons.sms_outlined,
        MessageChannel.whatsapp => Icons.chat_bubble_outline,
        MessageChannel.push => Icons.notifications_outlined,
      };
}

/// Icon for each recommended action, so drivers scan the card at a glance.
IconData actionIcon(String type) => switch (type) {
      'follow_access_instructions' => Icons.key_outlined,
      'leave_safe_place_or_call' => Icons.phone_in_talk_outlined,
      'flag_to_dispatch' => Icons.support_agent_outlined,
      'request_reschedule' => Icons.event_repeat_outlined,
      'send_eta_update' => Icons.timer_outlined,
      'follow_handling_request' => Icons.hearing_outlined,
      _ => Icons.route_outlined,
    };

IconData situationIcon(String type) => switch (type) {
      'access_instructions' => Icons.login_outlined,
      'recipient_unavailable' => Icons.person_search_outlined,
      'damaged_parcel' => Icons.inventory_2_outlined,
      'reschedule_request' => Icons.calendar_month_outlined,
      'delivery_update_requested' => Icons.update_outlined,
      'special_handling' => Icons.volunteer_activism_outlined,
      _ => Icons.sticky_note_2_outlined,
    };
