import 'package:flutter/material.dart';

import '../theme.dart';

/// Thẻ nền dùng chung cho mọi tab của app chủ phòng.
///
/// Đây là widget riêng chứ không dùng `Card` + `ThemeData.cardTheme`, vì kiểu
/// của `cardTheme` đổi từ `CardTheme` sang `CardThemeData` ở Flutter 3.27 —
/// không có cách viết nào biên dịch được trên cả hai bản. Dùng [Material] thì
/// bản Flutter nào cũng chạy, và vẫn có hiệu ứng gợn khi bấm vào `ListTile`
/// hay `InkWell` bên trong (điều mà `Container` không làm được).
class KaraCard extends StatelessWidget {
  const KaraCard({
    super.key,
    required this.child,
    this.color,
    this.padding,
    this.radius = 16,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final padding = this.padding;
    return Material(
      color: color ?? KaraColors.surface,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding, child: child),
    );
  }
}
