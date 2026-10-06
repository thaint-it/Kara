import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kara/core/room_controller.dart';
import 'package:kara/models/queue_item.dart';
import 'package:kara/models/song.dart';
import 'package:kara/services/storage_service.dart';
import 'package:kara/services/youtube_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thư mục tạm thay cho thư mục tài liệu của app khi chạy test.
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

Song song(String id, {String title = 'Bài hát', int seconds = 240}) => Song(
      videoId: id,
      title: title,
      channel: 'Kênh karaoke',
      durationSec: seconds,
      thumbUrl: Song.thumbnailFor(id),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;
  late RoomController room;
  late YoutubeService youtube;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kara_test');
    PathProviderPlatform.instance = _TempPathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});

    storage = await StorageService.open();
    youtube = YoutubeService();
    room = RoomController(
      storage: storage,
      youtube: youtube,
      deviceName: 'Kara test',
    );
    // Chế độ mặc định là TV và chưa ghép TV nào, nên không có lệnh nào ra mạng.
    await room.init();
  });

  tearDown(() async {
    room.dispose();
    youtube.dispose();
    // Chờ các lần ghi hàng chờ đang hoãn kết thúc rồi mới xoá thư mục tạm.
    await storage.flush();
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Không quan trọng với test.
    }
  });

  group('Chủ phòng thêm bài', () {
    test('bài đầu tiên được phát ngay', () {
      room.addByHost(song('aaa'));

      expect(room.current?.song.videoId, 'aaa');
      expect(room.current?.status, QueueStatus.playing);
      expect(room.queue, isEmpty);
    });

    /// Tiêu chí nghiệm thu: bấm chọn bài khi đang hát **không bao giờ** cắt
    /// ngang bài đang hát.
    test('bài thêm sau không cắt ngang bài đang hát', () {
      room.addByHost(song('aaa'));
      room.addByHost(song('bbb'));
      room.addByHost(song('ccc'), priority: true);

      expect(room.current?.song.videoId, 'aaa');
      expect(
        room.queue.map((i) => i.song.videoId),
        ['ccc', 'bbb'],
        reason: 'Ưu tiên chỉ chen lên đầu hàng chờ, không thay bài đang hát',
      );
    });
  });

  group('Khách yêu cầu & chủ phòng duyệt', () {
    test('mặc định phải chờ duyệt, không vào hàng chờ ngay', () {
      room.requestSong(song: song('aaa'), guestId: 'g1', guestName: 'Tuấn');

      expect(room.pending, hasLength(1));
      expect(room.pending.first.status, QueueStatus.pending);
      expect(room.queue, isEmpty);
      expect(room.current, isNull);
    });

    test('duyệt khi chưa có bài nào thì phát ngay', () {
      final item = room.requestSong(
        song: song('aaa'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );
      room.approve(item.uid);

      expect(room.pending, isEmpty);
      expect(room.current?.song.videoId, 'aaa');
      expect(room.current?.requestedBy.name, 'Tuấn');
    });

    test('duyệt kiểu "Ưu tiên" chen lên đầu hàng chờ', () {
      room.addByHost(song('dang-hat'));
      room.addByHost(song('cho-truoc'));

      final item = room.requestSong(
        song: song('uu-tien'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );
      room.approve(item.uid, priority: true);

      expect(room.current?.song.videoId, 'dang-hat');
      expect(room.queue.map((i) => i.song.videoId), ['uu-tien', 'cho-truoc']);
    });

    test('từ chối thì bài vào lịch sử với trạng thái bị từ chối', () {
      final item = room.requestSong(
        song: song('aaa'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );
      room.reject(item.uid);

      expect(room.pending, isEmpty);
      expect(room.queue, isEmpty);
      expect(room.history.first.status, QueueStatus.rejected);
    });

    test('duyệt tất cả giữ đúng thứ tự gửi', () {
      for (final id in ['a', 'b', 'c']) {
        room.requestSong(song: song(id), guestId: 'g1', guestName: 'Tuấn');
      }
      room.approveAll();

      expect(room.pending, isEmpty);
      expect(room.current?.song.videoId, 'a');
      expect(room.queue.map((i) => i.song.videoId), ['b', 'c']);
    });

    test('bật Tự động duyệt thì yêu cầu vào thẳng hàng chờ', () async {
      await room.updateSettings(room.settings.copyWith(autoApprove: true));

      room.requestSong(song: song('aaa'), guestId: 'g1', guestName: 'Tuấn');

      expect(room.pending, isEmpty);
      expect(room.current?.song.videoId, 'aaa');
    });

    test('khách được tin tưởng thì yêu cầu tự duyệt', () {
      room.upsertGuest('g1', 'Tuấn');
      room.setGuestTrusted('g1', true);

      room.requestSong(song: song('aaa'), guestId: 'g1', guestName: 'Tuấn');

      expect(room.pending, isEmpty);
      expect(room.current?.song.videoId, 'aaa');
    });

    test('tin tưởng một khách thì duyệt luôn các yêu cầu đang chờ của họ', () {
      room.requestSong(song: song('aaa'), guestId: 'g1', guestName: 'Tuấn');
      room.requestSong(song: song('bbb'), guestId: 'g2', guestName: 'Lan');

      room.setGuestTrusted('g1', true);

      expect(room.current?.song.videoId, 'aaa');
      expect(room.pending.map((i) => i.song.videoId), ['bbb']);
    });
  });

  group('Giới hạn số bài chờ mỗi khách', () {
    test('vượt giới hạn thì báo lỗi, các khách khác không bị ảnh hưởng', () {
      for (var i = 0; i < 3; i++) {
        room.requestSong(song: song('g1-$i'), guestId: 'g1', guestName: 'Tuấn');
      }

      expect(
        () => room.requestSong(
          song: song('g1-qua-nhieu'),
          guestId: 'g1',
          guestName: 'Tuấn',
        ),
        throwsA(isA<RoomException>()),
      );

      // Khách khác vẫn gửi được.
      room.requestSong(song: song('g2-0'), guestId: 'g2', guestName: 'Lan');
      expect(room.pendingCountOf('g2'), 1);
    });

    test('duyệt bớt thì khách gửi tiếp được', () {
      for (var i = 0; i < 3; i++) {
        room.requestSong(song: song('g1-$i'), guestId: 'g1', guestName: 'Tuấn');
      }
      room.approve(room.pending.first.uid);

      expect(
        () => room.requestSong(song: song('moi'), guestId: 'g1', guestName: 'Tuấn'),
        returnsNormally,
      );
    });
  });

  group('Khách tự huỷ yêu cầu', () {
    test('huỷ được yêu cầu của chính mình khi còn chờ duyệt', () {
      final item = room.requestSong(
        song: song('aaa'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );

      expect(room.cancelRequest(item.uid, 'g1'), isTrue);
      expect(room.pending, isEmpty);
      expect(room.history.first.status, QueueStatus.cancelled);
    });

    test('không huỷ được yêu cầu của người khác', () {
      final item = room.requestSong(
        song: song('aaa'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );

      expect(room.cancelRequest(item.uid, 'g2'), isFalse);
      expect(room.pending, hasLength(1));
    });
  });

  group('Sắp xếp hàng chờ', () {
    setUp(() {
      room.addByHost(song('dang-hat'));
      for (final id in ['a', 'b', 'c']) {
        room.addByHost(song(id));
      }
    });

    test('đưa lên đầu', () {
      room.moveToTop(room.queue[2].uid);
      expect(room.queue.map((i) => i.song.videoId), ['c', 'a', 'b']);
    });

    test('kéo thả đổi thứ tự', () {
      room.reorderQueue(0, 3);
      expect(room.queue.map((i) => i.song.videoId), ['b', 'c', 'a']);
    });

    test('xoá một bài', () {
      room.removeFromQueue(room.queue[1].uid);
      expect(room.queue.map((i) => i.song.videoId), ['a', 'c']);
    });

    test('xoá hết chỉ xoá hàng chờ, bài đang hát vẫn giữ', () {
      room.clearQueue();
      expect(room.queue, isEmpty);
      expect(room.current?.song.videoId, 'dang-hat');
    });

    test('hát ngay một bài trong hàng chờ: bài đang hát tính là bỏ qua', () async {
      await room.playItemNow(room.queue[1].uid);

      expect(room.current?.song.videoId, 'b');
      expect(room.history.first.song.videoId, 'dang-hat');
      expect(room.history.first.status, QueueStatus.skipped);
      expect(room.queue.map((i) => i.song.videoId), ['a', 'c']);
    });
  });

  group('Chuyển bài', () {
    test('qua bài thì bài đang hát vào lịch sử và bài kế tiếp được phát', () async {
      room.addByHost(song('aaa'));
      room.addByHost(song('bbb'));

      await room.skip();

      expect(room.current?.song.videoId, 'bbb');
      expect(room.history.first.song.videoId, 'aaa');
      expect(room.history.first.status, QueueStatus.skipped);
    });

    test('hết hàng chờ thì dừng, không phát gì thêm', () async {
      room.addByHost(song('aaa'));

      await room.skip();

      expect(room.current, isNull);
      expect(room.queue, isEmpty);
    });
  });

  group('Bài trùng', () {
    test('nhận ra bài đã có trong hàng chờ, đang hát, hoặc đang chờ duyệt', () {
      room.addByHost(song('dang-hat'));
      room.addByHost(song('trong-hang'));
      room.requestSong(song: song('cho-duyet'), guestId: 'g1', guestName: 'Tuấn');

      expect(room.isDuplicate('dang-hat'), isTrue);
      expect(room.isDuplicate('trong-hang'), isTrue);
      expect(room.isDuplicate('cho-duyet'), isTrue);
      expect(room.isDuplicate('chua-co'), isFalse);
    });

    test('bỏ qua chính nó khi so trùng', () {
      final item = room.requestSong(
        song: song('aaa'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );

      expect(room.isDuplicate('aaa', ignoreUid: item.uid), isFalse);
    });
  });

  group('Trạng thái gửi cho khách', () {
    test('kèm vị trí trong hàng chờ và danh sách bài của riêng khách', () {
      room.addByHost(song('dang-hat'));
      final mine = room.requestSong(
        song: song('cua-toi'),
        guestId: 'g1',
        guestName: 'Tuấn',
      );
      room.approve(mine.uid);
      room.requestSong(song: song('cua-nguoi-khac'), guestId: 'g2', guestName: 'Lan');

      final state = room.toStateJson(forGuestId: 'g1');

      expect(state['current'], isNotNull);
      expect((state['queue'] as List).first['position'], 1);
      expect(state['pendingCount'], 1);

      final mineList = state['mine'] as List;
      expect(mineList, hasLength(1));
      expect(mineList.first['song']['videoId'], 'cua-toi');
      expect(mineList.first['position'], 1);
    });

    test('tiêu đề bài hát được giữ nguyên để trang khách tự escape', () {
      room.addByHost(song('aaa', title: '<script>alert(1)</script> Bài ca'));

      final state = room.toStateJson();
      expect(
        state['current']['song']['title'],
        '<script>alert(1)</script> Bài ca',
      );
    });
  });

  group('Lưu và nạp lại khi tắt mở app', () {
    test('hàng chờ còn nguyên, bài đang hát quay về đầu hàng chờ', () async {
      room.addByHost(song('dang-hat'));
      room.addByHost(song('tiep-theo'));
      room.requestSong(song: song('cho-duyet'), guestId: 'g1', guestName: 'Tuấn');

      await storage.flush();

      final reopened = RoomController(
        storage: storage,
        youtube: youtube,
        deviceName: 'Kara test',
      );
      await reopened.init();

      expect(
        reopened.queue.map((i) => i.song.videoId),
        ['dang-hat', 'tiep-theo'],
        reason: 'Bài đang hát lúc tắt app được hát lại từ đầu',
      );
      expect(reopened.pending.map((i) => i.song.videoId), ['cho-duyet']);

      reopened.dispose();
    });
  });

  group('Lịch sử', () {
    test('chỉ giữ 50 bài gần nhất', () async {
      for (var i = 0; i < 55; i++) {
        room.addByHost(song('bai-$i'));
        await room.skip();
      }

      expect(room.history, hasLength(RoomController.historyLimit));
      expect(room.history.first.song.videoId, 'bai-54');
    });
  });

  group('Kết thúc buổi hát', () {
    setUp(() {
      room.addByHost(song('dang-hat'));
      room.addByHost(song('trong-hang'));
      room.requestSong(song: song('cho-duyet'), guestId: 'g1', guestName: 'Tuấn');
      room.upsertGuest('g2', 'Lan');
      room.setGuestTrusted('g2', true);
    });

    test('xoá hàng chờ, chờ duyệt và bài đang hát', () async {
      await room.endSession();

      expect(room.current, isNull);
      expect(room.queue, isEmpty);
      expect(room.pending, isEmpty);
      expect(room.hasSessionContent, isFalse);
    });

    test('dọn các mục bị bỏ qua / từ chối của buổi cũ khỏi lịch sử', () async {
      await room.skip(); // 'dang-hat' → bỏ qua
      room.reject(room.pending.first.uid); // 'cho-duyet' → từ chối
      expect(room.history, isNotEmpty);

      await room.endSession();

      expect(
        room.history,
        isEmpty,
        reason: 'Chỉ bài đã hát thật mới được giữ; mục bỏ qua/từ chối bị dọn',
      );
    });

    test('giữ khách đã tin tưởng, xoá khách lạ', () async {
      await room.endSession();

      expect(room.guests.map((g) => g.id), ['g2']);
      expect(room.guests.single.trusted, isTrue);
    });

    test('sinh mã phòng mới để ảnh QR cũ không dùng được nữa', () async {
      final before = room.roomCode;
      await room.endSession();

      expect(room.roomCode, isNot(before));
      expect(room.roomCode, hasLength(4));
    });

    test('giữ nguyên cài đặt', () async {
      await room.updateSettings(
        room.settings.copyWith(autoApprove: true, maxPendingPerGuest: 7),
      );
      await room.endSession();

      expect(room.settings.autoApprove, isTrue);
      expect(room.settings.maxPendingPerGuest, 7);
    });

    test('mốc bắt đầu buổi hát được đặt lại', () async {
      final before = room.sessionStartedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await room.endSession();

      expect(room.sessionStartedAt.isAfter(before), isTrue);
    });
  });

  group('Mở lại app', () {
    /// Hàng chờ phải sống sót qua việc tắt/mở app — đây là yêu cầu chính.
    test('mở lại ngay sau khi tắt thì hàng chờ còn nguyên', () async {
      room.addByHost(song('dang-hat'));
      room.addByHost(song('tiep-theo'));
      await storage.flush();

      final reopened = RoomController(
        storage: storage,
        youtube: youtube,
        deviceName: 'Kara test',
      );
      await reopened.init();

      expect(
        reopened.queue.map((i) => i.song.videoId),
        ['dang-hat', 'tiep-theo'],
      );
      reopened.dispose();
    });

    /// Nhưng mở lại sau nhiều ngày thì buổi hát cũ phải tự đóng.
    test('mở lại sau 7 ngày thì buổi hát cũ đã kết thúc', () async {
      final stale = DateTime.now().subtract(const Duration(days: 7));
      storage.saveRoom(RoomSnapshot(
        current: null,
        queue: [
          QueueItem(
            uid: 'u1',
            song: song('bai-cu'),
            requestedBy: Requester.host,
            status: QueueStatus.queued,
            createdAt: stale,
          ),
        ],
        pending: const [],
        history: const [],
        guests: const [],
        sessionStartedAt: stale,
        lastActivityAt: stale,
      ));
      await storage.flush();

      final codeBefore = storage.roomCode();
      final reopened = RoomController(
        storage: storage,
        youtube: youtube,
        deviceName: 'Kara test',
      );
      await reopened.init();

      expect(reopened.queue, isEmpty, reason: 'Hàng chờ cũ đã được dọn');
      expect(reopened.current, isNull);
      expect(reopened.roomCode, isNot(codeBefore));
      reopened.dispose();
    });

    test('buổi hát cũ đóng lại nhưng lịch sử "Đã hát" vẫn còn', () async {
      final stale = DateTime.now().subtract(const Duration(days: 7));
      storage.saveRoom(RoomSnapshot(
        current: null,
        queue: const [],
        pending: const [],
        history: [
          QueueItem(
            uid: 'h1',
            song: song('bai-da-hat'),
            requestedBy: Requester.host,
            status: QueueStatus.played,
            createdAt: stale,
            playedAt: stale,
          ),
        ],
        guests: const [],
        sessionStartedAt: stale,
        lastActivityAt: stale,
      ));
      await storage.flush();

      final reopened = RoomController(
        storage: storage,
        youtube: youtube,
        deviceName: 'Kara test',
      );
      await reopened.init();

      expect(
        reopened.history.map((i) => i.song.videoId),
        ['bai-da-hat'],
        reason: 'Bấm "Hát lại" cho bài buổi trước vẫn phải dùng được',
      );
      reopened.dispose();
    });

    test('tắt tự kết thúc thì hàng chờ cũ vẫn còn sau 7 ngày', () async {
      await storage.saveSettings(
        room.settings.copyWith(sessionIdleHours: 0),
      );
      final stale = DateTime.now().subtract(const Duration(days: 7));
      storage.saveRoom(RoomSnapshot(
        current: null,
        queue: [
          QueueItem(
            uid: 'u1',
            song: song('bai-cu'),
            requestedBy: Requester.host,
            status: QueueStatus.queued,
            createdAt: stale,
          ),
        ],
        pending: const [],
        history: const [],
        guests: const [],
        sessionStartedAt: stale,
        lastActivityAt: stale,
      ));
      await storage.flush();

      final reopened = RoomController(
        storage: storage,
        youtube: youtube,
        deviceName: 'Kara test',
      );
      await reopened.init();

      expect(reopened.queue.map((i) => i.song.videoId), ['bai-cu']);
      reopened.dispose();
    });
  });
}
