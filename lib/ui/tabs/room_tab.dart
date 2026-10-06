import 'package:flutter/material.dart';

import '../../lounge/tv_controller.dart';
import '../../models/queue_item.dart';
import '../../models/room_settings.dart';
import '../../models/song.dart';
import '../app.dart';
import '../pair_tv_page.dart';
import '../theme.dart';
import '../widgets/kara_card.dart';
import '../widgets/phone_player_view.dart';
import '../widgets/qr_panel.dart';
import '../widgets/song_tile.dart';

/// Tab "Phòng": thẻ Đang hát, nút điều khiển to, dòng Tiếp theo, mã QR thu
/// gọn, trạng thái TV (mục 11).
class RoomTab extends StatelessWidget {
  const RoomTab({super.key});

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Phòng hát',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            _ModeChip(mode: room.mode),
          ],
        ),
        const SizedBox(height: 12),
        if (room.mode == PlaybackMode.tv) const _TvStatusCard(),
        if (room.outsideVideoId != null) const _OutsideWarning(),
        const SizedBox(height: 12),
        const _NowPlayingCard(),
        const SizedBox(height: 12),
        const _UpNextLine(),
        const SizedBox(height: 14),
        const QrPanel(),
        const SizedBox(height: 18),
        const _HistorySection(),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final PlaybackMode mode;

  @override
  Widget build(BuildContext context) => KaraTag(
        mode == PlaybackMode.tv ? 'Phát trên TV' : 'Phát trên điện thoại',
        color: KaraColors.ok,
      );
}

/// Trạng thái ghép nối TV + nút ghép / ghép lại (mục 7.5).
class _TvStatusCard extends StatelessWidget {
  const _TvStatusCard();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final link = room.tvLink;

    final color = switch (link.state) {
      TvLinkState.connected => KaraColors.ok,
      TvLinkState.connecting => KaraColors.warn,
      TvLinkState.unpaired => KaraColors.muted,
      TvLinkState.disconnected => KaraColors.accent,
    };

    return KaraCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.tv, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                link.description,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PairTvPage()),
              ),
              child: Text(link.state == TvLinkState.unpaired ? 'Ghép TV' : 'Đổi TV'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cảnh báo khi ai đó dùng remote TV chọn bài khác (mục 7.4).
class _OutsideWarning extends StatelessWidget {
  const _OutsideWarning();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.read(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: KaraCard(
        color: KaraColors.accentWash,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: KaraColors.accent),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'TV đang phát bài ngoài hàng chờ',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: room.reclaimPlayback,
                child: const Text('Quay lại hàng chờ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final current = room.current;

    return KaraCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ĐANG HÁT',
              style: TextStyle(
                fontSize: 15,
                letterSpacing: 1,
                color: KaraColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (current == null)
              const Text(
                'Chưa có bài nào. Thêm bài ở tab Tìm bài hoặc để khách quét QR.',
                style: TextStyle(fontSize: 16, color: KaraColors.muted),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SongThumb(song: current.song, width: 120),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          current.requestedBy.name,
                          style: const TextStyle(
                            fontSize: 15,
                            color: KaraColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            _ProgressRow(
              position: room.position,
              duration: room.duration,
            ),
            if (room.isAd) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const KaraTag('Đang có quảng cáo', color: KaraColors.warn),
                  const Spacer(),
                  if (room.adSkippable)
                    CompactButton(
                      label: 'Bỏ quảng cáo',
                      icon: Icons.fast_forward,
                      primary: true,
                      onPressed: room.skipAd,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const _Controls(),
            const SizedBox(height: 6),
            const _VolumeRow(),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.position, required this.duration});

  final double position;
  final double duration;

  @override
  Widget build(BuildContext context) {
    final value = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: KaraColors.line,
            valueColor: const AlwaysStoppedAnimation(KaraColors.accent),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDuration(position.round()),
              style: const TextStyle(fontSize: 15, color: KaraColors.muted),
            ),
            Text(
              formatDuration(duration.round()),
              style: const TextStyle(fontSize: 15, color: KaraColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final hasSomething = room.current != null || room.queue.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: room.current == null ? null : room.restart,
            child: const Icon(Icons.replay),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: hasSomething ? room.togglePlayPause : null,
            icon: Icon(room.isPlaying ? Icons.pause : Icons.play_arrow, size: 26),
            label: Text(room.isPlaying ? 'Tạm dừng' : 'Phát'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: hasSomething ? () => confirmSkip(context, room) : null,
            child: const Icon(Icons.skip_next),
          ),
        ),
      ],
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    return Row(
      children: [
        const Icon(Icons.volume_down, color: KaraColors.muted),
        Expanded(
          child: Slider(
            value: room.settings.volume.toDouble(),
            max: 100,
            divisions: 20,
            label: '${room.settings.volume}',
            onChanged: (v) => room.setVolume(v.round()),
          ),
        ),
        const Icon(Icons.volume_up, color: KaraColors.muted),
      ],
    );
  }
}

class _UpNextLine extends StatelessWidget {
  const _UpNextLine();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final next = room.upNext;

    return KaraCard(
      color: KaraColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.playlist_play, color: KaraColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                next == null
                    ? 'Hàng chờ đang trống'
                    : 'Tiếp theo: ${next.requestedBy.name} – ${next.song.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Đã hát" – 50 bài gần nhất, bấm để yêu cầu lại (mục 5.5).
class _HistorySection extends StatelessWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final played = room.history
        .where((i) => i.status == QueueStatus.played)
        .toList(growable: false);

    if (played.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Đã hát (${played.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        for (final item in played.take(10))
          SongTile(
            song: item.song,
            subtitle: item.requestedBy.name,
            actions: [
              CompactButton(
                label: 'Hát lại',
                icon: Icons.replay,
                onPressed: () {
                  RoomScope.read(context).addByHost(item.song);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Đã thêm "${item.song.title}"')),
                  );
                },
              ),
            ],
          ),
        if (played.length > 10)
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _HistoryPage()),
            ),
            child: Text('Xem tất cả ${played.length} bài'),
          ),
      ],
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final played = room.history
        .where((i) => i.status == QueueStatus.played)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text('Đã hát (${played.length})')),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: played.length,
        itemBuilder: (context, i) => SongTile(
          song: played[i].song,
          subtitle: played[i].requestedBy.name,
          actions: [
            CompactButton(
              label: 'Hát lại',
              icon: Icons.replay,
              onPressed: () => RoomScope.read(context).addByHost(played[i].song),
            ),
          ],
        ),
      ),
    );
  }
}
