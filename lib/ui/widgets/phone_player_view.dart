import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/room_controller.dart';
import '../app.dart';
import '../tabs/pending_tab.dart';
import '../theme.dart';
import 'seek_bar.dart';

/// Trình phát nhúng dạng thu gọn, nằm cố định phía trên các tab.
///
/// [playerKey] là GlobalKey dùng chung với [PhonePlayerFullscreen]: nhờ nó mà
/// WebView được "đổi chỗ" trong cây widget thay vì bị tạo lại, nên video
/// không bị nạp lại khi vào/ra toàn màn hình.
class PhonePlayerStrip extends StatelessWidget {
  const PhonePlayerStrip({super.key, required this.playerKey});

  final GlobalKey playerKey;

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);

    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PlayerSurface(playerKey: playerKey),
            Positioned(
              right: 8,
              bottom: 8,
              child: _RoundIconButton(
                icon: Icons.fullscreen,
                tooltip: 'Toàn màn hình',
                onPressed: () => room.setPhoneFullscreen(true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phát toàn màn hình, xoay ngang, có bảng duyệt bài dạng nổi để mở mà không
/// dừng video (mục 8).
class PhonePlayerFullscreen extends StatefulWidget {
  const PhonePlayerFullscreen({super.key, required this.playerKey});

  final GlobalKey playerKey;

  @override
  State<PhonePlayerFullscreen> createState() => _PhonePlayerFullscreenState();
}

class _PhonePlayerFullscreenState extends State<PhonePlayerFullscreen> {
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PlayerSurface(playerKey: widget.playerKey),
            if (_controlsVisible) _controls(context, room),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, RoomController room) {
    final current = room.current;
    final upNext = room.upNext;

    return Container(
      color: Colors.black54,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current?.song.title ?? 'Chưa có bài nào',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (upNext != null)
                      Text(
                        'Tiếp theo: ${upNext.requestedBy.name} – ${upNext.song.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          color: KaraColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
              _RoundIconButton(
                icon: Icons.fullscreen_exit,
                tooltip: 'Thoát toàn màn hình',
                onPressed: () => room.setPhoneFullscreen(false),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundIconButton(
                icon: Icons.replay,
                tooltip: 'Hát lại từ đầu',
                onPressed: room.current == null ? null : room.restart,
              ),
              const SizedBox(width: 18),
              _RoundIconButton(
                icon: room.isPlaying ? Icons.pause : Icons.play_arrow,
                tooltip: room.isPlaying ? 'Tạm dừng' : 'Phát',
                big: true,
                onPressed: room.togglePlayPause,
              ),
              const SizedBox(width: 18),
              _RoundIconButton(
                icon: Icons.skip_next,
                tooltip: 'Qua bài',
                onPressed: room.queue.isEmpty && room.current == null
                    ? null
                    : () => confirmSkip(context, room),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              const Expanded(child: SeekBar(compact: true)),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _openPendingSheet(context),
                icon: const Icon(Icons.how_to_reg, size: 18),
                label: Text('Chờ duyệt (${room.pending.length})'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bảng duyệt bài nổi lên trên video – video vẫn phát bình thường.
  void _openPendingSheet(BuildContext context) {
    final room = RoomScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KaraColors.surface,
      isScrollControlled: true,
      builder: (_) => RoomScope(
        room: room,
        server: RoomScope.serverOf(context),
        child: const FractionallySizedBox(
          heightFactor: 0.9,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Chờ duyệt',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(child: PendingTab(showAppBar: false)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hỏi xác nhận trước khi qua bài (mục 5.4).
Future<void> confirmSkip(BuildContext context, RoomController room) async {
  final next = room.upNext;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: KaraColors.surface,
      title: const Text('Qua bài này?'),
      content: Text(
        next == null
            ? 'Hàng chờ đang trống, qua bài sẽ dừng phát.'
            : 'Bài kế tiếp: ${next.song.title}',
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Thôi'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Qua bài'),
        ),
      ],
    ),
  );
  if (ok == true) await room.skip();
}

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({required this.playerKey});

  final GlobalKey playerKey;

  @override
  Widget build(BuildContext context) {
    final controller = RoomScope.of(context).phoneTarget.webView;
    if (controller == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return WebViewWidget(key: playerKey, controller: controller);
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.big = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool big;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        iconSize: big ? 40 : 26,
        style: IconButton.styleFrom(
          backgroundColor: big ? KaraColors.accent : Colors.black54,
          foregroundColor: Colors.white,
          minimumSize: Size.square(big ? 72 : 48),
        ),
        icon: Icon(icon),
      );
}

