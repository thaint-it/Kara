import 'package:flutter/material.dart';

import '../../models/room_settings.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';

/// Tab "Chờ duyệt": mỗi yêu cầu có 3 nút Thêm cuối hàng / Ưu tiên / Từ chối,
/// kèm nút Duyệt tất cả (mục 5.3).
class PendingTab extends StatelessWidget {
  const PendingTab({super.key, this.showAppBar = true});

  /// Tắt khi hiện trong bottom sheet lúc đang phát toàn màn hình.
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final pending = room.pending;

    if (pending.isEmpty) {
      return const EmptyHint(
        icon: Icons.how_to_reg_outlined,
        message: 'Chưa có yêu cầu nào.\nKhách quét mã QR ở tab Phòng để chọn bài.',
      );
    }

    return Column(
      children: [
        if (showAppBar)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Chờ duyệt (${pending.length})',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: room.approveAll,
                  icon: const Icon(Icons.done_all, size: 20),
                  label: const Text('Duyệt tất cả'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            itemCount: pending.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = pending[index];
              final duplicate =
                  room.isDuplicate(item.song.videoId, ignoreUid: item.uid);

              return SongTile(
                song: item.song,
                subtitle: '${item.requestedBy.name} • ${item.song.channel}',
                tags: [
                  // Bài trùng được đánh dấu để chủ phòng biết (mục 5.3).
                  if (duplicate)
                    const KaraTag('Đã có trong hàng chờ', color: KaraColors.warn),
                  if (item.song.embeddable == false &&
                      room.mode == PlaybackMode.phone)
                    const KaraTag('Không phát được trên điện thoại',
                        color: KaraColors.warn),
                ],
                actions: [
                  CompactButton(
                    label: 'Thêm cuối hàng',
                    icon: Icons.playlist_add,
                    primary: true,
                    onPressed: () => room.approve(item.uid),
                  ),
                  CompactButton(
                    label: 'Ưu tiên',
                    icon: Icons.vertical_align_top,
                    onPressed: () => room.approve(item.uid, priority: true),
                  ),
                  CompactButton(
                    label: 'Từ chối',
                    icon: Icons.close,
                    danger: true,
                    onPressed: () => room.reject(item.uid),
                  ),
                  if (!item.requestedBy.isHost)
                    CompactButton(
                      label: 'Tin tưởng',
                      icon: Icons.verified_user_outlined,
                      onPressed: () => room.setGuestTrusted(
                        item.requestedBy.guestId,
                        true,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
