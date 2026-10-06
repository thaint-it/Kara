import 'package:flutter/material.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';

/// Tab "Hàng chờ": kéo thả đổi thứ tự, vuốt để xoá (mục 5.4 + 11).
class QueueTab extends StatelessWidget {
  const QueueTab({super.key});

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final queue = room.queue;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Hàng chờ (${queue.length})',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (queue.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClear(context),
                  child: const Text('Xoá hết'),
                ),
            ],
          ),
        ),
        if (queue.isEmpty)
          const Expanded(
            child: EmptyHint(
              icon: Icons.queue_music_outlined,
              message: 'Hàng chờ đang trống.\n'
                  'Thêm bài ở tab Tìm bài, hoặc duyệt yêu cầu của khách.',
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
              itemCount: queue.length,
              onReorder: room.reorderQueue,
              proxyDecorator: (child, _, __) => Material(
                color: KaraColors.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
              itemBuilder: (context, index) {
                final item = queue[index];
                return Dismissible(
                  key: ValueKey(item.uid),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: KaraColors.accent,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => room.removeFromQueue(item.uid),
                  child: SongTile(
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 22, right: 2),
                        child: Icon(Icons.drag_handle, color: KaraColors.muted),
                      ),
                    ),
                    song: item.song,
                    subtitle: '#${index + 1} • ${item.requestedBy.name}',
                    actions: [
                      CompactButton(
                        label: 'Hát ngay',
                        icon: Icons.play_arrow,
                        primary: true,
                        onPressed: () => room.playItemNow(item.uid),
                      ),
                      if (index > 0)
                        CompactButton(
                          label: 'Lên đầu',
                          icon: Icons.vertical_align_top,
                          onPressed: () => room.moveToTop(item.uid),
                        ),
                      CompactButton(
                        label: 'Xoá',
                        icon: Icons.close,
                        danger: true,
                        onPressed: () => room.removeFromQueue(item.uid),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final room = RoomScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KaraColors.surface,
        title: const Text('Xoá hết hàng chờ?'),
        content: const Text(
          'Bài đang hát vẫn tiếp tục, chỉ xoá các bài đang chờ.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá hết'),
          ),
        ],
      ),
    );
    if (ok == true) room.clearQueue();
  }
}
