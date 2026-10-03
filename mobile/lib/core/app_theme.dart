import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/delivery.dart';

/// ShiftFlow Courier UI design tokens.
///
/// Ported verbatim from the Google Stitch project "Delivery Driver App
/// Interface" (ShiftFlow Courier UI design system). Screens pull colours from
/// these tokens instead of hard-coding them, so the whole product can be
/// re-skinned from here.
///
/// Source: `design/project.json` -> `designTheme.namedColors` / `designMd`.
class AppTheme {
  AppTheme._();

  // ------------------------------------------------------------------ canvas
  /// Deep slate canvas (`background` / `surface` / `surface-dim`).
  static const Color bg = Color(0xFF0F141B);

  /// Card surface (`surface-container`).
  static const Color surface = Color(0xFF1B2027);

  /// Nested surface: inputs, note blocks, inner tiles (`surface-container-low`).
  static const Color surfaceAlt = Color(0xFF171C23);

  /// Raised surface: dialogs, snackbars, chips (`surface-container-high`).
  static const Color surfaceHigh = Color(0xFF252A32);

  /// Highest surface: step badges, inert tracks (`surface-container-highest`).
  static const Color surfaceHighest = Color(0xFF30353D);

  /// Lowest surface: inset pill bars (`surface-container-lowest`).
  static const Color surfaceLowest = Color(0xFF090F15);

  /// Bright surface used for `surface-bright`.
  static const Color surfaceBright = Color(0xFF343941);

  /// Hairline separators and card borders (`outline-variant`).
  static const Color hairline = Color(0xFF3C4A42);

  // -------------------------------------------------------------------- text
  static const Color ink = Color(0xFFDEE2EC);
  static const Color inkMuted = Color(0xFFBBCABF);
  static const Color inkFaint = Color(0xFF86948A);

  // ------------------------------------------------------------------ brand
  /// Mint green: the signature action colour (`primary`).
  static const Color brand = Color(0xFF4EDEA3);

  /// Deeper mint for gradient edges and pressed states (`primary-container`).
  static const Color brandDark = Color(0xFF10B981);

  /// High-contrast foreground for primary mint actions (`on-primary`).
  static const Color onBrand = Color(0xFF003824);

  /// Sky blue accent for informational and secondary actions (`secondary`).
  static const Color accent = Color(0xFF7BD0FF);

  /// Deeper blue used for secondary containers (`secondary-container`).
  static const Color accentDark = Color(0xFF00A6E0);

  /// High-contrast foreground for secondary blue actions (`on-secondary`).
  static const Color onAccent = Color(0xFF00354A);

  // --------------------------------------------------------------- semantic
  /// Completed / delivered (`primary-fixed`, a touch brighter than `brand`).
  static const Color success = Color(0xFF6FFBBE);

  /// Amber warning and customer notes (`tertiary`).
  static const Color warning = Color(0xFFFFB95F);

  /// Deeper amber for tertiary containers (`tertiary-container`).
  static const Color warningDark = Color(0xFFE29100);

  /// Error red (`error`).
  static const Color danger = Color(0xFFFFB4AB);

  // -------------------------------------------------------------- gradients
  /// Signature mint gradient for brand moments (primary -> primary-container).
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brand, brandDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Slate wash used behind hero areas.
  static const LinearGradient heroGradient = LinearGradient(
    colors: [surface, surfaceAlt, bg],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The design's shift-progress fill: blue -> mint.
  static const LinearGradient progressGradient = LinearGradient(
    colors: [accent, brand],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Mint bloom, layered behind heroes and key callouts.
  static RadialGradient bloom({double alpha = 0.28}) => RadialGradient(
        center: Alignment.topRight,
        radius: 1.15,
        colors: [
          brand.withValues(alpha: alpha),
          brandDark.withValues(alpha: alpha * 0.35),
          Colors.transparent
        ],
      );

  // --------------------------------------------------------------- elevation
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  /// Shared card treatment used across the app (`rounded-2xl`, solid surface).
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: cardShadow,
      );

  /// Softer variant for tiles nested inside a card (`rounded-xl`).
  static BoxDecoration get innerDecoration => BoxDecoration(
        color: surfaceLowest,
        borderRadius: BorderRadius.circular(12),
      );

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: brand,
      onPrimary: onBrand,
      primaryContainer: brandDark,
      onPrimaryContainer: Color(0xFF00422B),
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accentDark,
      onSecondaryContainer: Color(0xFF00374D),
      tertiary: warning,
      onTertiary: Color(0xFF472A00),
      tertiaryContainer: warningDark,
      onTertiaryContainer: Color(0xFF523200),
      error: danger,
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: bg,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      surfaceContainerHighest: surfaceHighest,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerLow: surfaceAlt,
      surfaceContainer: surface,
      outline: inkFaint,
      outlineVariant: hairline,
      shadow: Colors.black,
      inverseSurface: ink,
      onInverseSurface: bg,
      inversePrimary: Color(0xFF006C49),
      scrim: Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: ink,
          fontFamily: 'Inter',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.33,
        ),
      ),

      // ShiftFlow type scale: 36/28/22/18 headlines, 16/14/12 body,
      // 14/12/11 labels. Weights follow the design (700/600/500/400).
      textTheme: const TextTheme(
        displaySmall: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -1.08,
            height: 1.22), // display-metric
        headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -0.56,
            height: 1.29), // headline-lg
        headlineSmall: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: -0.22,
            height: 1.27), // headline-md
        titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: 0,
            height: 1.33), // headline-sm
        titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: 0,
            height: 1.35),
        titleSmall: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: ink, height: 1.3),
        bodyLarge: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w500, color: ink, height: 1.5),
        bodyMedium:
            TextStyle(fontSize: 14, color: ink, height: 1.43), // body-md
        bodySmall: TextStyle(
            fontSize: 12, color: inkMuted, height: 1.33, letterSpacing: 0.12),
        labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: 0.28,
            height: 1.29), // label-lg
        labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: inkMuted,
            letterSpacing: 0.48,
            height: 1.33), // label-md
        labelSmall: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: inkFaint,
            letterSpacing: 0.66,
            height: 1.27), // label-badge
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: inkFaint, fontSize: 14),
        labelStyle: const TextStyle(color: inkMuted, fontSize: 14),
        floatingLabelStyle:
            const TextStyle(color: brand, fontWeight: FontWeight.w600),
        prefixIconColor: inkMuted,
        suffixIconColor: inkMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: brand, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.6),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: onBrand,
          disabledBackgroundColor: surfaceHigh,
          disabledForegroundColor: inkFaint,
          shadowColor: brand.withValues(alpha: 0.35),
          elevation: 4,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.28),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          disabledForegroundColor: inkFaint,
          backgroundColor: surface,
          side: const BorderSide(color: hairline),
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: inkMuted),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceAlt,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: brand.withValues(alpha: 0.16),
        height: 72,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              fontFamily: 'Inter'),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? brand : inkMuted,
            size: 23,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: hairline),
        backgroundColor: surface,
        selectedColor: brand,
        checkmarkColor: onBrand,
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: ink),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      dividerTheme:
          const DividerThemeData(color: hairline, space: 1, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        elevation: 8,
        contentTextStyle:
            const TextStyle(color: ink, fontSize: 14, height: 1.35),
        actionTextColor: brand,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: hairline),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: hairline),
        ),
        titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
            letterSpacing: -0.2,
            fontFamily: 'Inter'),
        contentTextStyle: const TextStyle(
            fontSize: 14, color: inkMuted, height: 1.43, fontFamily: 'Inter'),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brand,
        linearTrackColor: surfaceHighest,
        circularTrackColor: surfaceHighest,
        refreshBackgroundColor: surfaceHigh,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: inkMuted,
        textColor: ink,
        contentPadding: EdgeInsets.zero,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? onBrand : inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? brand : surfaceHighest,
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
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: hairline),
        ),
        textStyle:
            const TextStyle(fontSize: 14, color: ink, fontFamily: 'Inter'),
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
  /// Toned to the ShiftFlow palette so status reads at a glance while driving.
  Color get color => switch (this) {
        DeliveryStatus.pending => AppTheme.inkMuted,
        DeliveryStatus.inTransit => AppTheme.warning,
        DeliveryStatus.failed => AppTheme.danger,
        DeliveryStatus.delivered => AppTheme.success,
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
