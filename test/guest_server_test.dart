import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kara/core/room_controller.dart';
import 'package:kara/models/song.dart';
import 'package:kara/server/guest_server.dart';
import 'package:kara/services/storage_service.dart';
import 'package:kara/services/youtube_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;
  late YoutubeService youtube;
  late RoomController room;
  late GuestServer server;
  late HttpClient client;
  late Uri base;

  Map<String, dynamic> songJson(String id) => Song(
        videoId: id,
        title: 'Bài $id',
        channel: 'Kênh',
        durationSec: 240,
        thumbUrl: Song.thumbnailFor(id),
      ).toJson();

  Future<({int status, Map<String, dynamic> body})> call(
    String method,
    String path, {
    Map<String, dynamic>? json,
  }) async {
    final request = await client.openUrl(method, base.resolve(path));
    if (json != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(json));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null; // Trang tĩnh và lỗi 404 trả về text thuần.
    }
    return (
      status: response.statusCode,
      body: decoded is Map<String, dynamic> ? decoded : {'text': text},
    );
  }

  setUp(() async {
    // flutter_test cài sẵn một HttpClient giả trả 400 cho mọi request để chặn
    // truy cập mạng ngoài ý muốn; test này cần HTTP thật tới server nội bộ.
    HttpOverrides.global = null;

    tempDir = await Directory.systemTemp.createTemp('kara_server_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});

    storage = await StorageService.open();
    youtube = YoutubeService();
    room = RoomController(
      storage: storage,
      youtube: youtube,
      deviceName: 'Kara test',
    );
    await room.init();

    server = GuestServer(room);
    // Cổng 0 để hệ thống tự chọn, tránh đụng cổng 8080 của máy đang chạy test.
    final uri = await server.start(port: 0);
    base = Uri.parse('http://127.0.0.1:${uri.port}');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    room.dispose();
    youtube.dispose();
    await storage.flush();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Không quan trọng với test.
    }
  });

  group('GET /api/state', () {
    test('trả trạng thái phòng và ghi nhận khách', () async {
      final res = await call('GET', '/api/state?guestId=g1&name=Tu%E1%BA%A5n');

      expect(res.status, 200);
      expect(res.body['roomCode'], room.roomCode);
      expect(res.body['queue'], isEmpty);
      expect(res.body['mine'], isEmpty);
      expect(room.guests.map((g) => g.name), contains('Tuấn'));
    });
  });

  group('POST /api/request', () {
    test('thiếu mã phòng thì bị từ chối', () async {
      final res = await call('POST', '/api/request', json: {
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('aaa'),
      });

      expect(res.status, 403);
      expect(room.pending, isEmpty);
    });

    test('sai mã phòng thì bị từ chối', () async {
      final res = await call('POST', '/api/request', json: {
        'room': '0000',
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('aaa'),
      });

      expect(res.status, 403);
      expect(room.pending, isEmpty);
    });

    test('đúng mã phòng thì tạo yêu cầu chờ duyệt', () async {
      final res = await call('POST', '/api/request', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('aaa'),
      });

      expect(res.status, 200);
      expect(res.body['ok'], isTrue);
      expect(res.body['item']['status'], 'pending');
      expect(room.pending, hasLength(1));
      expect(room.pending.first.requestedBy.name, 'Tuấn');
    });

    test('thiếu thông tin bài hát thì báo lỗi', () async {
      final res = await call('POST', '/api/request', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'name': 'Tuấn',
      });

      expect(res.status, 400);
    });

    test('vượt giới hạn bài chờ của khách thì trả 429', () async {
      for (var i = 0; i < 3; i++) {
        await call('POST', '/api/request', json: {
          'room': room.roomCode,
          'guestId': 'g1',
          'name': 'Tuấn',
          'song': songJson('bai-$i'),
        });
      }

      final res = await call('POST', '/api/request', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('bai-qua-nhieu'),
      });

      expect(res.status, 429);
      expect(room.pending, hasLength(3));
    });

    test('giới hạn 10 yêu cầu mỗi phút cho mỗi khách', () async {
      // Tự động duyệt để không vướng giới hạn "bài đang chờ duyệt".
      await room.updateSettings(room.settings.copyWith(autoApprove: true));

      for (var i = 0; i < 10; i++) {
        final res = await call('POST', '/api/request', json: {
          'room': room.roomCode,
          'guestId': 'g1',
          'name': 'Tuấn',
          'song': songJson('bai-$i'),
        });
        expect(res.status, 200, reason: 'yêu cầu thứ ${i + 1}');
      }

      final res = await call('POST', '/api/request', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('bai-11'),
      });
      expect(res.status, 429);
    });
  });

  group('POST /api/request/cancel', () {
    test('khách huỷ được yêu cầu của chính mình', () async {
      final created = await call('POST', '/api/request', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('aaa'),
      });
      final uid = created.body['item']['uid'] as String;

      final res = await call('POST', '/api/request/cancel', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'uid': uid,
      });

      expect(res.status, 200);
      expect(room.pending, isEmpty);
    });

    test('không huỷ được yêu cầu của người khác', () async {
      final created = await call('POST', '/api/request', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'name': 'Tuấn',
        'song': songJson('aaa'),
      });
      final uid = created.body['item']['uid'] as String;

      final res = await call('POST', '/api/request/cancel', json: {
        'room': room.roomCode,
        'guestId': 'g2',
        'uid': uid,
      });

      expect(res.status, 400);
      expect(room.pending, hasLength(1));
    });
  });

  group('POST /api/control', () {
    test('mặc định khách không được điều khiển', () async {
      room.addByHost(Song.fromJson(songJson('aaa')));
      room.addByHost(Song.fromJson(songJson('bbb')));

      final res = await call('POST', '/api/control', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'action': 'next',
      });

      expect(res.status, 403);
      expect(room.current?.song.videoId, 'aaa');
    });

    test('bật "Cho khách điều khiển" thì qua bài được', () async {
      await room.updateSettings(room.settings.copyWith(guestControl: true));
      room.addByHost(Song.fromJson(songJson('aaa')));
      room.addByHost(Song.fromJson(songJson('bbb')));

      final res = await call('POST', '/api/control', json: {
        'room': room.roomCode,
        'guestId': 'g1',
        'action': 'next',
      });

      expect(res.status, 200);
      expect(room.current?.song.videoId, 'bbb');
    });
  });

  group('GET /api/search', () {
    test('từ khoá rỗng trả danh sách rỗng, không gọi YouTube', () async {
      final res = await call('GET', '/api/search?q=%20');

      expect(res.status, 200);
      expect(res.body['results'], isEmpty);
    });
  });

  group('Đường dẫn không có', () {
    test('trả 404', () async {
      final res = await call('GET', '/khong-ton-tai.txt');
      expect(res.status, 404);
    });
  });
}
