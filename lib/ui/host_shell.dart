import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/room_controller.dart';
import '../models/room_settings.dart';
import 'app.dart';
import 'tabs/pending_tab.dart';
import 'tabs/queue_tab.dart';
import 'tabs/room_tab.dart';
import 'tabs/search_tab.dart';
import 'tabs/settings_tab.dart';
import 'theme.dart';
import 'widgets/phone_player_view.dart';

/// Khung app chủ phòng: 5 tab dưới + trình phát trên điện thoại (nếu đang
/// dùng chế độ đó) nằm cố định phía trên.
class HostShell extends StatefulWidget {
  const HostShell({super.key});

  @override
  State<HostShell> createState() => _HostShellState();
}

class _HostShellState extends State<HostShell> {
  /// Giữ WebView sống khi chuyển qua lại giữa thu gọn và toàn màn hình:
  /// widget có GlobalKey được "đổi chỗ" chứ không bị tạo lại.
  final _playerKey = GlobalKey();

  int _tab = 0;
  RoomController? _room;
  StreamSubscription<RoomToast>? _toastSub;
  int _lastPendingCount = 0;
  bool _wakelockOn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final room = RoomScope.read(context);
    if (identical(room, _room)) return;

    _room?.removeListener(_onRoomChanged);
    _toastSub?.cancel();

    _room = room;
    _lastPendingCount = room.pending.length;
    room.addListener(_onRoomChanged);
    _toastSub = room.toasts.listen(_onToast);
  }

  @override
  void dispose() {
    _room?.removeListener(_onRoomChanged);
    _toastSub?.cancel();
    if (_wakelockOn) WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _onRoomChanged() {
    final room = _room!;

    // Yêu cầu mới → rung + badge ở tab "Chờ duyệt" (mục 5.3).
    if (room.pending.length > _lastPendingCount) {
      HapticFeedback.vibrate();
    }
    _lastPendingCount = room.pending.length;

    _syncWakelock(room);
  }

  /// Giữ màn hình sáng khi đang phát trên điện thoại (mục 8).
  ///
  /// Trên iPhone thì giữ sáng cả khi phát ra TV: iOS không cho app chạy web
  /// server sau khi khoá màn hình, nên màn hình tắt là khách mất kết nối
  /// (mục 13). Android có foreground service nên không cần.
  void _syncWakelock(RoomController room) {
    final needed = (room.mode == PlaybackMode.phone && room.current != null) ||
        (Platform.isIOS && room.current != null);
    if (needed == _wakelockOn) return;
    _wakelockOn = needed;
    needed ? WakelockPlus.enable() : WakelockPlus.disable();
  }

  void _onToast(RoomToast toast) {
    // Chỉ hiện trên app chủ những thông báo không nhắm riêng một khách nào.
    if (toast.guestId != null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(toast.message),
        backgroundColor:
            toast.isError ? KaraColors.accent : KaraColors.surfaceHigh,
        duration: const Duration(seconds: 3),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final showPlayer =
        room.mode == PlaybackMode.phone && room.phoneTarget.webView != null;

    if (showPlayer && room.phoneFullscreen) {
      return PhonePlayerFullscreen(playerKey: _playerKey);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showPlayer) PhonePlayerStrip(playerKey: _playerKey),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: const [
                  RoomTab(),
                  PendingTab(),
                  QueueTab(),
                  SearchTab(),
                  SettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Phòng',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: room.pending.isNotEmpty,
              label: Text('${room.pending.length}'),
              child: const Icon(Icons.how_to_reg_outlined),
            ),
            selectedIcon: const Icon(Icons.how_to_reg),
            label: 'Chờ duyệt',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: room.queue.isNotEmpty,
              label: Text('${room.queue.length}'),
              child: const Icon(Icons.queue_music_outlined),
            ),
            selectedIcon: const Icon(Icons.queue_music),
            label: 'Hàng chờ',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Tìm bài',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Cài đặt',
          ),
        ],
      ),
    );
  }
}
