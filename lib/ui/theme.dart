import 'package:flutter/material.dart';

/// Giao diện tối (phòng hát thường tắt đèn), chữ to, nút to dễ bấm khi đang
/// cầm mic — yêu cầu chung ở mục 11 của đặc tả.
///
/// Các màu mờ được viết sẵn dạng ARGB thay vì gọi `withOpacity` / `withValues`:
/// hai hàm đó đổi tên giữa các bản Flutter, còn hằng số thì bản nào cũng chạy.
class KaraColors {
  static const bg = Color(0xFF0D0D12);
  static const surface = Color(0xFF17171F);
  static const surfaceHigh = Color(0xFF1F1F2B);
  static const line = Color(0xFF2B2B3A);
  static const text = Color(0xFFF2F2F7);
  static const muted = Color(0xFF9A9AAD);
  static const accent = Color(0xFFFF4D6D);
  static const ok = Color(0xFF38D39F);
  static const warn = Color(0xFFFFB020);

  /// Nền ô đang chọn ở thanh tab dưới (accent 18%).
  static const accentSoft = Color(0x2EFF4D6D);

  /// Nền thẻ cảnh báo, ví dụ "TV đang phát bài ngoài hàng chờ" (accent 12%).
  static const accentWash = Color(0x1FFF4D6D);

  /// Nền nhãn thời lượng đè trên ảnh thu nhỏ (đen 80%).
  static const scrim = Color(0xCC000000);
}

ThemeData buildKaraTheme() {
  const scheme = ColorScheme.dark(
    primary: KaraColors.accent,
    onPrimary: Colors.white,
    secondary: KaraColors.ok,
    surface: KaraColors.surface,
    onSurface: KaraColors.text,
    error: KaraColors.accent,
  );

  final base = ThemeData.from(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: KaraColors.bg,
    canvasColor: KaraColors.bg,
    dividerColor: KaraColors.line,
    textTheme: base.textTheme.apply(fontSizeFactor: 1.0).copyWith(
          // Không có cỡ chữ nào dưới 15px.
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 15),
          labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 15),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KaraColors.bg,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: KaraColors.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    // Cố ý không đặt `cardTheme`: kiểu của nó đổi từ `CardTheme` sang
    // `CardThemeData` ở Flutter 3.27, nên code sẽ không biên dịch được trên cả
    // hai bản. Thẻ dùng widget `KaraCard` (ui/widgets/kara_card.dart) thay thế.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: KaraColors.text,
        side: const BorderSide(color: KaraColors.line),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KaraColors.surfaceHigh,
      hintStyle: const TextStyle(color: KaraColors.muted, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: KaraColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: KaraColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: KaraColors.accent),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: KaraColors.surface,
      indicatorColor: KaraColors.accentSoft,
      height: 70,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: KaraColors.surfaceHigh,
      contentTextStyle: TextStyle(color: KaraColors.text, fontSize: 16),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      textColor: KaraColors.text,
      iconColor: KaraColors.muted,
      titleTextStyle: TextStyle(fontSize: 16, color: KaraColors.text),
      subtitleTextStyle: TextStyle(fontSize: 15, color: KaraColors.muted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? KaraColors.accent
            : KaraColors.muted,
      ),
    ),
  );
}
