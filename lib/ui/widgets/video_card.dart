import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../theme.dart';

/// Thẻ kết quả tìm kiếm bố cục giống app YouTube trên điện thoại: ảnh to toàn
/// chiều ngang, bên dưới là avatar kênh, tên bài, "kênh · lượt xem · ngày" và
/// nút ⋮ — người dùng đã quen nên không phải học lại.
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.song,
    this.tags = const [],
    this.onTap,
    this.onMore,
  });

  final Song song;
  final List<Widget> tags;
  final VoidCallback? onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final meta = [
      song.channel,
      if (song.viewCountText != null) song.viewCountText!,
      if (song.publishedText != null) song.publishedText!,
    ].where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(song: song),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChannelAvatar(name: song.channel),
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
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: KaraColors.muted,
                          ),
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 6, children: tags),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tuỳ chọn',
                    onPressed: onMore ?? onTap,
                    icon: const Icon(Icons.more_vert, color: KaraColors.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: KaraColors.surfaceHigh),
            Image.network(
              song.thumbUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.music_note,
                size: 48,
                color: KaraColors.muted,
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: KaraColors.scrim,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  song.durationText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

/// Kết quả tìm kiếm không kèm ảnh kênh, nên vẽ vòng tròn có chữ cái đầu như
/// YouTube làm với kênh chưa đặt ảnh đại diện.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.name, this.size = 38});

  final String name;
  final double size;

  static const _palette = [
    Color(0xFFE53935),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF039BE5),
    Color(0xFF00897B),
    Color(0xFF7CB342),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    final color = _palette[trimmed.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
