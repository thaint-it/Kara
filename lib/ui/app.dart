import 'dart:io';

import 'package:flutter/material.dart';

import '../core/room_controller.dart';
import '../server/guest_server.dart';
import '../services/room_service_keeper.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import 'host_shell.dart';
import 'theme.dart';

/// Dựng các service theo đúng thứ tự phụ thuộc: web server phải chạy trước
/// khi bộ phát trên điện thoại nạp trang `/player`.
class KaraApp extends StatefulWidget {
  const KaraApp({super.key});

  @override
  State<KaraApp> createState() => _KaraAppState();
}

class _KaraAppState extends State<KaraApp> {
  late final Future<RoomController> _ready = _boot();

  RoomController? _room;
  GuestServer? _server;
  YoutubeService? _youtube;

  Future<RoomController> _boot() async {
    final storage = await StorageService.open();
    final youtube = YoutubeService();
    _youtube = youtube;

    final room = RoomController(
      storage: storage,
      youtube: youtube,
      deviceName: await _deviceName(),
    );
    _room = room;

    final server = GuestServer(room);
    _server = server;
    try {
      room.attachServer(await server.start());
      // Thông báo thường trực để Android không đóng băng tiến trình khi khoá
      // màn hình – nếu không, khách sẽ mất kết nối giữa buổi hát.
      await RoomServiceKeeper.start(
        address: room.guestUrl?.toString() ?? 'Đang chờ WiFi',
      );
    } catch (e) {
      debugPrint('Không bật được web server khách: $e');
    }

    await room.init();
    return room;
  }

  /// Tên hiện lên TV khi kết nối.
  static Future<String> _deviceName() async {
    try {
      return 'Kara – ${Platform.localHostname}';
    } catch (_) {
      return 'Kara';
    }
  }

  @override
  void dispose() {
    RoomServiceKeeper.stop();
    _server?.stop();
    _room?.dispose();
    _youtube?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RoomController>(
        future: _ready,
        builder: (context, snapshot) {
          final room = snapshot.data;
          return MaterialApp(
            title: 'Karaoke Hàng Chờ',
            debugShowCheckedModeBanner: false,
            theme: buildKaraTheme(),
            // RoomScope bọc ngoài Navigator (qua `builder`) để các trang được
            // push thêm (Ghép TV, Lịch sử…) cũng nằm dưới nó.
            builder: (context, child) => room == null
                ? child!
                : RoomScope(room: room, server: _server!, child: child!),
            home: snapshot.hasError
                ? _StartupError(error: '${snapshot.error}')
                : room == null
                    ? const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      )
                    : const HostShell(),
          );
        },
      );
}

/// Cho phép mọi widget con lấy [RoomController] và tự dựng lại khi trạng thái
/// phòng thay đổi.
class RoomScope extends InheritedNotifier<RoomController> {
  const RoomScope({
    super.key,
    required RoomController room,
    required this.server,
    required super.child,
  }) : super(notifier: room);

  final GuestServer server;

  static RoomController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RoomScope>();
    assert(scope != null, 'RoomScope chưa có trong cây widget');
    return scope!.notifier!;
  }

  /// Dùng khi chỉ cần gọi hành động, không cần dựng lại theo trạng thái.
  static RoomController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RoomScope>();
    assert(scope != null, 'RoomScope chưa có trong cây widget');
    return scope!.notifier!;
  }

  static GuestServer serverOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<RoomScope>();
    return scope!.server;
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Không mở được phòng',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(error, style: const TextStyle(color: KaraColors.muted)),
            ],
          ),
        ),
      );
}
