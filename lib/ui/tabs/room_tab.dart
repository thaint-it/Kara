import 'package:flutter/material.dart';

import '../../core/room_controller.dart';
import '../../lounge/tv_controller.dart';
import '../../models/queue_item.dart';
import '../../models/room_settings.dart';
import '../app.dart';
import '../pair_tv_page.dart';
import '../theme.dart';
import '../widgets/kara_card.dart';
import '../widgets/phone_player_view.dart';
import '../widgets/qr_panel.dart';
import '../widgets/seek_bar.dart';
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
      TvLinkState.released => KaraColors.muted,
    };

    final released = link.state == TvLinkState.released;
    final canRelease = link.state == TvLinkState.connected ||
        link.state == TvLinkState.disconnected ||
        link.state == TvLinkState.connecting;

    return KaraCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tv, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    link.description,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PairTvPage()),
                  ),
                  child: Text(
                    link.state == TvLinkState.unpaired ? 'Ghép TV' : 'Đổi TV',
                  ),
                ),
              ],
            ),
            if (released)
              Padding(
                padding: const EdgeInsets.only(left: 36, right: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Dùng remote xem YouTube bình thường. Bấm Phát để hát tiếp.',
                        style: TextStyle(fontSize: 15, color: KaraColors.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: room.reconnectTv,
                      child: const Text('Kết nối lại'),
                    ),
                  ],
                ),
              )
            else if (canRelease)
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: TextButton.icon(
                  onPressed: () => _confirmRelease(context, room),
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Trả TV về YouTube'),
                  style: TextButton.styleFrom(
                    foregroundColor: KaraColors.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRelease(BuildContext context, RoomController room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trả TV về YouTube?'),
        content: const Text(
          'App sẽ dừng bài đang hát và ngắt kết nối để mọi người dùng remote '
          'xem YouTube bình thường. Hàng chờ vẫn giữ nguyên; bấm Phát là hát '
          'tiếp, không phải nhập mã lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trả TV'),
          ),
        ],
      ),
    );
    if (ok == true) await room.releaseTv();
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
            const SeekBar(),
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
