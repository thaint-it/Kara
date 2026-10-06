import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../theme.dart';

/// Ảnh thu nhỏ 16:9 có thời lượng đè góc, giống kết quả tìm kiếm YouTube.
class SongThumb extends StatelessWidget {
  const SongThumb({super.key, required this.song, this.width = 136});

  final Song song;
  final double width;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: width * 9 / 16,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: KaraColors.surfaceHigh),
              Image.network(
                song.thumbUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.music_note,
                  color: KaraColors.muted,
                ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: KaraColors.scrim,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    song.durationText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Nhãn nhỏ: "Đã có trong hàng chờ", "Chờ duyệt", tên người yêu cầu…
class KaraTag extends StatelessWidget {
  const KaraTag(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KaraColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(fontSize: 15, color: c)),
    );
  }
}

/// Một dòng bài hát dùng lại ở tất cả các tab của app chủ phòng.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.subtitle,
    this.tags = const [],
    this.actions = const [],
    this.leading,
    this.onTap,
  });

  final Song song;
  final String? subtitle;
  final List<Widget> tags;
  final List<Widget> actions;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      song.channel,
      if (song.viewCountText != null) song.viewCountText!,
      if (song.publishedText != null) song.publishedText!,
    ].where((s) => s.isNotEmpty).join(' • ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            SongThumb(song: song),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle ?? meta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: KaraColors.muted),
                  ),
                  if (tags.isNotEmpty || actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [...tags, ...actions],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút nhỏ gọn trong hàng hành động của [SongTile].
class CompactButton extends StatelessWidget {
  const CompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
        Text(label),
      ],
    );

    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 4);

    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: padding,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: padding,
        foregroundColor: danger ? KaraColors.accent : KaraColors.text,
        side: BorderSide(color: danger ? KaraColors.accent : KaraColors.line),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: child,
    );
  }
}

/// Khung trống dùng chung cho các tab.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: KaraColors.line),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: KaraColors.muted),
              ),
            ],
          ),
        ),
      );
}
