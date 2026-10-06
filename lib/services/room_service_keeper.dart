import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Giữ cho tiến trình app sống khi chủ phòng khoá màn hình (mục 12).
///
/// Android chỉ cho phép một tiến trình chạy nền lâu nếu nó có foreground
/// service kèm thông báo thường trực. Web server và bộ phát vẫn nằm ở isolate
/// chính; task handler dưới đây không làm gì cả, nó chỉ tồn tại để hệ thống
/// không đóng băng tiến trình.
///
/// iOS không cho chạy server khi app ở nền lâu (mục 13), nên ở iOS lớp này
/// không làm gì.
class RoomServiceKeeper {
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static void configure() {
    if (!_supported) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kara_room',
        channelName: 'Phòng karaoke đang mở',
        channelDescription:
            'Giữ web server cho khách chọn bài khi màn hình đã tắt.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Bật thông báo thường trực. [address] là địa chỉ khách đang dùng.
  static Future<void> start({required String address}) async {
    if (!_supported) return;

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Phòng karaoke đang mở',
        notificationText: address,
      );
      return;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 2301,
      notificationTitle: 'Phòng karaoke đang mở',
      notificationText: address,
      callback: startRoomKeeperTask,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('Không bật được foreground service: ${result.error}');
    }
  }

  static Future<void> stop() async {
    if (!_supported) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void startRoomKeeperTask() {
  FlutterForegroundTask.setTaskHandler(_RoomKeeperHandler());
}

/// Không có việc gì để làm định kỳ; sự tồn tại của service là mục đích.
class _RoomKeeperHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
