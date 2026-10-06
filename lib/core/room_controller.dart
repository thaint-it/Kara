import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../lounge/lounge_events.dart';
import '../lounge/tv_controller.dart';
import '../models/guest.dart';
import '../models/queue_item.dart';
import '../models/room_settings.dart';
import '../models/song.dart';
import '../player/auto_advance.dart';
import '../player/phone_playback_target.dart';
import '../player/playback_target.dart';
import '../player/tv_playback_target.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import 'session_policy.dart';

/// Thông báo ngắn gửi cho chủ phòng và/hoặc một khách cụ thể.
@immutable
class RoomToast {
  const RoomToast(this.message, {this.guestId, this.isError = false});

  final String message;

  /// `null` = gửi cho mọi người.
  final String? guestId;
  final bool isError;
}

/// Toàn bộ trạng thái của phòng hát. Chủ phòng chính là "máy chủ", nên mọi
/// thay đổi (từ UI chủ phòng hay từ khách qua HTTP) đều đi qua lớp này.
class RoomController extends ChangeNotifier {
  RoomController({
    required StorageService storage,
    required YoutubeService youtube,
    required String deviceName,
  })  : _storage = storage,
        _youtube = youtube {
    _settings = storage.loadSettings();
    _roomCode = storage.roomCode();

    tv = TvController(
      deviceName: deviceName,
      onAuthChanged: storage.saveTvAuth,
    );
    _tvTarget = TvPlaybackTarget(tv);
    _phoneTarget = PhonePlaybackTarget(playerUrl: () => playerUrl);

    tv.link.addListener(_onTvLinkChanged);
    _tvTarget.updates.listen((u) => _onPlaybackUpdate(u, PlaybackMode.tv));
    _phoneTarget.updates
        .listen((u) => _onPlaybackUpdate(u, PlaybackMode.phone));
  }

  static const historyLimit = 50;
  static const _uuid = Uuid();

  final StorageService _storage;
  final YoutubeService _youtube;

  late final TvController tv;
  late final TvPlaybackTarget _tvTarget;
  late final PhonePlaybackTarget _phoneTarget;

  final _guard = AutoAdvanceGuard();
  final _policy = const SessionPolicy();
  final _toasts = StreamController<RoomToast>.broadcast();

  /// Thông báo cho UI chủ phòng và cho khách qua WebSocket.
  Stream<RoomToast> get toasts => _toasts.stream;

  YoutubeService get youtube => _youtube;

  PhonePlaybackTarget get phoneTarget => _phoneTarget;

  // --------------------------------------------------------------- trạng thái

  late RoomSettings _settings;
  late String _roomCode;

  QueueItem? _current;
  final List<QueueItem> _queue = [];
  final List<QueueItem> _pending = [];
  final List<QueueItem> _history = [];
  final Map<String, Guest> _guests = {};

  PlayerState _playerState = PlayerState.stopped;
  double _basePosition = 0;
  DateTime _basePositionAt = DateTime.now();
  double _duration = 0;
  bool _adSkippable = false;
  bool _isAd = false;

  /// Nếu ai đó dùng remote TV chọn bài khác, lưu videoId đó ở đây và **không
  /// giành lại** quyền phát (mục 7.4).
  String? _outsideVideoId;

  /// Địa chỉ web server nhúng, có sau khi server bật.
  Uri? _serverUri;

  /// Trình phát trên điện thoại đang chiếm toàn màn hình.
  bool _phoneFullscreen = false;

  // ------------------------------------------------- mốc thời gian buổi hát

  DateTime _sessionStartedAt = DateTime.now();
  DateTime _lastActivityAt = DateTime.now();

  /// Lần TV bắt đầu mất kết nối; `null` khi TV đang nối hoặc khi không dùng TV.
  DateTime? _tvOfflineSince;

  Timer? _ticker;
  Timer? _sessionTimer;

  RoomSettings get settings => _settings;

  String get roomCode => _roomCode;

  QueueItem? get current => _current;

  List<QueueItem> get queue => List.unmodifiable(_queue);

  List<QueueItem> get pending => List.unmodifiable(_pending);

  List<QueueItem> get history => List.unmodifiable(_history);

  List<Guest> get guests => List.unmodifiable(_guests.values);

  PlayerState get playerState => _playerState;

  double get duration => _duration;

  bool get adSkippable => _adSkippable;

  bool get isAd => _isAd;

  String? get outsideVideoId => _outsideVideoId;

  bool get phoneFullscreen => _phoneFullscreen;

  TvLink get tvLink => tv.link.value;

  PlaybackMode get mode => _settings.mode;

  PlaybackTarget get target =>
      mode == PlaybackMode.tv ? _tvTarget : _phoneTarget;

  bool get isPlaying => _playerState == PlayerState.playing;

  /// Bài kế tiếp để hiện thanh "Tiếp theo: …".
  QueueItem? get upNext => _queue.isEmpty ? null : _queue.first;

  /// Vị trí phát hiện tại, nội suy giữa hai lần bộ phát báo về để thanh tiến
  /// độ chạy mượt mỗi giây.
  double get position {
    if (_playerState != PlayerState.playing) return _basePosition;
    final elapsed =
        DateTime.now().difference(_basePositionAt).inMilliseconds / 1000.0;
    final p = _basePosition + elapsed;
    return _duration > 0 ? p.clamp(0, _duration) : p;
  }

  /// Địa chỉ khách quét QR để vào: `http://<ip>:8080/?room=1234`.
  Uri? get guestUrl => _serverUri?.replace(queryParameters: {'room': _roomCode});

  /// Trang trình phát nhúng, phục vụ bởi chính server này.
  ///
  /// Dùng `127.0.0.1` chứ không dùng IP WiFi: trang vẫn có một origin `http://`
  /// thật (điều kiện của YouTube IFrame API) nhưng không chết khi mất WiFi hay
  /// khi IP đổi giữa chừng.
  Uri get playerUrl => Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: _serverUri?.port ?? 8080,
        path: '/player',
      );

  // ------------------------------------------------------------- khởi động

  Future<void> init() async {
    final snapshot = await _storage.loadRoom();
    _queue.addAll(snapshot.queue);
    _pending.addAll(snapshot.pending);
    _history.addAll(snapshot.history);
    for (final g in snapshot.guests) {
      _guests[g.id] = g;
    }

    final now = DateTime.now();
    _sessionStartedAt = snapshot.sessionStartedAt ?? now;
    _lastActivityAt = snapshot.lastActivityAt ?? now;
    _tvOfflineSince = snapshot.tvOfflineSince;

    // Bài đang hát lúc tắt app được đưa về đầu hàng chờ để hát lại từ đầu.
    final interrupted = snapshot.current;
    if (interrupted != null) {
      _queue.insert(0, interrupted.copyWith(status: QueueStatus.queued));
    }

    // Kiểm tra ngay khi mở app: tắt app cả tuần rồi mở lại thì buổi hát cũ
    // phải được đóng trước khi UI hiện hàng chờ đã cũ.
    await _checkSession();

    if (mode == PlaybackMode.tv) {
      tv.start(auth: _storage.loadTvAuth());
    }
    await target.attach();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_playerState != PlayerState.playing) return;
      // Đang hát thì buổi hát đương nhiên còn sống.
      _lastActivityAt = DateTime.now();
      notifyListeners();
    });
    _sessionTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkSession(),
    );

    notifyListeners();
  }

  void attachServer(Uri uri) {
    _serverUri = uri;
    notifyListeners();
  }

  /// Lệnh gửi cho TV / trình phát là bất đồng bộ, nên một lệnh đang bay vẫn có
  /// thể gọi [notifyListeners] sau khi app đã đóng phòng.
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _sessionTimer?.cancel();
    tv.link.removeListener(_onTvLinkChanged);
    _tvTarget.dispose();
    _phoneTarget.dispose();
    tv.dispose();
    _toasts.close();
    _storage.flush();
    super.dispose();
  }

  // ------------------------------------------------------------- cài đặt

  Future<void> updateSettings(RoomSettings next) async {
    final previous = _settings;
    _settings = next;
    await _storage.saveSettings(next);

    if (next.mode != previous.mode) {
      await _switchMode(previous.mode, next.mode);
    } else if (next.volume != previous.volume) {
      await target.setVolume(next.volume);
    }

    // Bật "Tự động duyệt" thì các yêu cầu đang chờ vào thẳng hàng chờ.
    if (next.autoApprove && !previous.autoApprove) approveAll();

    notifyListeners();
  }

  Future<void> setMode(PlaybackMode mode) =>
      updateSettings(_settings.copyWith(mode: mode));

  Future<void> setVolume(int volume) async {
    _settings = _settings.copyWith(volume: volume);
    await target.setVolume(volume);
    await _storage.saveSettings(_settings);
    notifyListeners();
  }

  /// Đổi chế độ phát giữa chừng: bài đang phát được phát tiếp ở thiết bị mới
  /// từ đầu (mục 5.1).
  Future<void> _switchMode(PlaybackMode from, PlaybackMode to) async {
    final playing = _current;

    final oldTarget = from == PlaybackMode.tv ? _tvTarget : _phoneTarget;
    await oldTarget.stop();
    if (from == PlaybackMode.phone) {
      _phoneFullscreen = false;
      await _phoneTarget.detach();
    }

    if (to == PlaybackMode.tv) {
      tv.start(auth: _storage.loadTvAuth());
    }
    await target.attach();
    await target.setVolume(_settings.volume);

    if (playing != null) {
      _guard.reset();
      await _loadIntoTarget(playing.song);
    }
    _toast('Đã chuyển sang ${to.label.toLowerCase()}');
  }

  void setPhoneFullscreen(bool value) {
    if (_phoneFullscreen == value) return;
    _phoneFullscreen = value;
    notifyListeners();
  }

  void setGuestTrusted(String guestId, bool trusted) {
    final guest = _guests[guestId];
    if (guest == null) return;
    _guests[guestId] = guest.copyWith(trusted: trusted);
    if (trusted) {
      // Duyệt luôn các yêu cầu đang chờ của người này.
      for (final item in _pending.where((i) => i.requestedBy.guestId == guestId).toList()) {
        approve(item.uid);
      }
    }
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------------- buổi hát

  DateTime get sessionStartedAt => _sessionStartedAt;

  DateTime get lastActivityAt => _lastActivityAt;

  DateTime? get tvOfflineSince => _tvOfflineSince;

  /// Buổi hát đang "sống": có bài đang hát, có bài chờ, hoặc có yêu cầu chờ duyệt.
  bool get hasSessionContent =>
      _current != null || _queue.isNotEmpty || _pending.isNotEmpty;

  /// Ghi nhận có người đang dùng phòng, để đồng hồ tự kết thúc lùi lại.
  void _markActivity() => _lastActivityAt = DateTime.now();

  void _onTvLinkChanged() {
    final state = tv.link.value.state;

    // Chỉ tính đồng hồ "TV mất kết nối" khi thật sự đang dùng một TV đã ghép.
    if (mode == PlaybackMode.tv && tv.isPaired) {
      if (state == TvLinkState.connected) {
        _tvOfflineSince = null;
      } else if (state == TvLinkState.disconnected) {
        // `connecting` không tính: nó chỉ là một nhịp chớp giữa hai lần thử.
        _tvOfflineSince ??= DateTime.now();
      }
    } else {
      _tvOfflineSince = null;
    }

    notifyListeners();
  }

  Future<void> _checkSession() async {
    final reason = _policy.evaluate(
      now: DateTime.now(),
      lastActivityAt: _lastActivityAt,
      idleTimeout: _settings.sessionIdleTimeout,
      tvOfflineSince: _tvOfflineSince,
      queueEmpty: !hasSessionContent,
    );
    if (reason != null) await endSession(reason);
  }

  /// Đóng buổi hát: xoá hàng chờ, yêu cầu chờ duyệt và khách lạ, sinh mã phòng
  /// mới. Giữ lại cài đặt, token TV, lịch sử "Đã hát" và những khách đã được
  /// "tin tưởng" — người nhà thì không nên phải tick lại mỗi buổi.
  ///
  /// Đây là chỗ duy nhất trong app xoá dữ liệu của người dùng.
  Future<void> endSession([
    SessionEndReason reason = SessionEndReason.manual,
  ]) async {
    final hadContent = hasSessionContent;

    await target.stop();

    _current = null;
    _queue.clear();
    _pending.clear();
    // Lịch sử chỉ giữ bài đã hát thật; bỏ các mục bị từ chối / huỷ của buổi cũ.
    _history.removeWhere((i) => i.status != QueueStatus.played);
    _guests.removeWhere((_, guest) => !guest.trusted);

    _playerState = PlayerState.stopped;
    _basePosition = 0;
    _basePositionAt = DateTime.now();
    _duration = 0;
    _adSkippable = false;
    _isAd = false;
    _outsideVideoId = null;
    _guard.reset();

    _tvOfflineSince = null;
    _sessionStartedAt = DateTime.now();
    _lastActivityAt = DateTime.now();

    // Mã phòng mới: ảnh QR ai chụp từ buổi trước không dùng được nữa.
    _roomCode = await _storage.regenerateRoomCode();

    _persist();
    await _storage.flush();

    if (hadContent || reason == SessionEndReason.manual) {
      _toast('${reason.title}. ${reason.detail}');
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- khách

  /// Khách gửi `hello` qua WebSocket hoặc gọi API lần đầu.
  Guest upsertGuest(String guestId, String name) {
    final existing = _guests[guestId];
    final guest = existing == null
        ? Guest(id: guestId, name: name, lastSeen: DateTime.now())
        : existing.copyWith(
            name: name.trim().isEmpty ? existing.name : name.trim(),
            lastSeen: DateTime.now(),
          );
    _guests[guestId] = guest;
    _persist();
    return guest;
  }

  int pendingCountOf(String guestId) =>
      _pending.where((i) => i.requestedBy.guestId == guestId).length;

  /// Bài này đã có trong hàng chờ / đang hát / đang chờ duyệt chưa.
  bool isDuplicate(String videoId, {String? ignoreUid}) {
    bool match(QueueItem i) =>
        i.song.videoId == videoId && i.uid != ignoreUid;
    return (_current != null && match(_current!)) ||
        _queue.any(match) ||
        _pending.any(match);
  }

  // ------------------------------------------------------- yêu cầu & duyệt

  /// Khách yêu cầu một bài. Trả về mục đã tạo, hoặc ném [RoomException] khi
  /// vượt giới hạn.
  QueueItem requestSong({
    required Song song,
    required String guestId,
    required String guestName,
  }) {
    final guest = upsertGuest(guestId, guestName);

    final autoApprove = _settings.autoApprove || guest.trusted;
    if (!autoApprove && pendingCountOf(guestId) >= _settings.maxPendingPerGuest) {
      throw RoomException(
        'Bạn đang có ${_settings.maxPendingPerGuest} bài chờ duyệt. '
        'Đợi chủ phòng duyệt rồi gửi thêm nhé.',
      );
    }

    final item = QueueItem(
      uid: _uuid.v4(),
      song: _markEmbedInfo(song),
      requestedBy: Requester(guestId: guestId, name: guest.name),
      status: autoApprove ? QueueStatus.queued : QueueStatus.pending,
      createdAt: DateTime.now(),
      approvedAt: autoApprove ? DateTime.now() : null,
    );

    _markActivity();

    if (autoApprove) {
      _enqueue(item);
      _toast('Đã thêm "${song.title}" vào hàng chờ', guestId: guestId);
    } else {
      _pending.add(item);
      _toast('Đã gửi yêu cầu, chờ chủ phòng duyệt', guestId: guestId);
    }

    _persist();
    notifyListeners();
    return item;
  }

  /// Chủ phòng thêm bài trực tiếp, không cần duyệt.
  QueueItem addByHost(Song song, {bool priority = false}) {
    final item = QueueItem(
      uid: _uuid.v4(),
      song: _markEmbedInfo(song),
      requestedBy: Requester.host,
      status: QueueStatus.queued,
      createdAt: DateTime.now(),
      approvedAt: DateTime.now(),
    );
    _markActivity();
    _enqueue(item, priority: priority);
    _persist();
    notifyListeners();
    return item;
  }

  /// Duyệt một yêu cầu. [priority] = hát ngay sau bài hiện tại.
  void approve(String uid, {bool priority = false}) {
    final index = _pending.indexWhere((i) => i.uid == uid);
    if (index < 0) return;
    final item = _pending.removeAt(index).copyWith(
          status: QueueStatus.queued,
          approvedAt: DateTime.now(),
        );
    _markActivity();
    _enqueue(item, priority: priority);
    _toast(
      'Bài "${item.song.title}" đã được duyệt',
      guestId: item.requestedBy.guestId,
    );
    _persist();
    notifyListeners();
  }

  void approveAll() {
    for (final item in _pending.toList()) {
      approve(item.uid);
    }
  }

  void reject(String uid) {
    final index = _pending.indexWhere((i) => i.uid == uid);
    if (index < 0) return;
    final item = _pending.removeAt(index).copyWith(status: QueueStatus.rejected);
    _pushHistory(item);
    _toast(
      'Bài "${item.song.title}" bị từ chối',
      guestId: item.requestedBy.guestId,
    );
    _persist();
    notifyListeners();
  }

  /// Khách tự huỷ yêu cầu của mình khi còn "Chờ duyệt".
  bool cancelRequest(String uid, String guestId) {
    final index = _pending.indexWhere(
      (i) => i.uid == uid && i.requestedBy.guestId == guestId,
    );
    if (index < 0) return false;
    final item = _pending.removeAt(index).copyWith(status: QueueStatus.cancelled);
    _pushHistory(item);
    _persist();
    notifyListeners();
    return true;
  }

  /// Tất cả yêu cầu của một khách, mới nhất trước – cho tab "Bài của tôi".
  List<QueueItem> itemsOf(String guestId) {
    final mine = [
      if (_current?.requestedBy.guestId == guestId) _current!,
      ..._pending.where((i) => i.requestedBy.guestId == guestId),
      ..._queue.where((i) => i.requestedBy.guestId == guestId),
      ..._history.where((i) => i.requestedBy.guestId == guestId),
    ];
    return mine;
  }

  /// Vị trí trong hàng chờ, đếm từ 1. `null` nếu không nằm trong hàng.
  int? queuePositionOf(String uid) {
    final i = _queue.indexWhere((e) => e.uid == uid);
    return i < 0 ? null : i + 1;
  }

  // -------------------------------------------------------------- hàng chờ

  void _enqueue(QueueItem item, {bool priority = false}) {
    if (priority) {
      _queue.insert(0, item);
    } else {
      _queue.add(item);
    }
    // Đang không có bài nào mà có bài mới được duyệt → phát ngay (mục 5.4).
    if (_current == null) _playNext();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex.clamp(0, _queue.length), item);
    _persist();
    notifyListeners();
  }

  void moveToTop(String uid) {
    final i = _queue.indexWhere((e) => e.uid == uid);
    if (i <= 0) return;
    _queue.insert(0, _queue.removeAt(i));
    _persist();
    notifyListeners();
  }

  void removeFromQueue(String uid) {
    final i = _queue.indexWhere((e) => e.uid == uid);
    if (i < 0) return;
    final item = _queue.removeAt(i).copyWith(status: QueueStatus.cancelled);
    _pushHistory(item);
    _persist();
    notifyListeners();
  }

  void clearQueue() {
    for (final item in _queue) {
      _pushHistory(item.copyWith(status: QueueStatus.cancelled));
    }
    _queue.clear();
    _persist();
    notifyListeners();
  }

  // ------------------------------------------------------------ điều khiển

  Future<void> togglePlayPause() async {
    _markActivity();
    if (_current == null) {
      if (_queue.isNotEmpty) await _playNext();
      return;
    }
    if (isPlaying) {
      _playerState = PlayerState.paused;
      _basePosition = position;
      _basePositionAt = DateTime.now();
      await target.pause();
    } else {
      _playerState = PlayerState.playing;
      _basePositionAt = DateTime.now();
      await target.play();
    }
    notifyListeners();
  }

  /// Qua bài (UI hỏi xác nhận trước khi gọi).
  Future<void> skip() async {
    _finishCurrent(QueueStatus.skipped);
    await _playNext();
  }

  /// Hát lại từ đầu.
  Future<void> restart() async {
    final song = _current?.song;
    if (song == null) return;
    _basePosition = 0;
    _basePositionAt = DateTime.now();
    await target.seek(0);
    await target.play();
    notifyListeners();
  }

  Future<void> skipAd() => target.skipAd();

  /// "Quay lại hàng chờ" khi TV đang phát bài ngoài hàng chờ.
  Future<void> reclaimPlayback() async {
    _outsideVideoId = null;
    final song = _current?.song;
    if (song == null) {
      await _playNext();
    } else {
      _guard.reset();
      await _loadIntoTarget(song);
    }
    notifyListeners();
  }

  Future<void> playItemNow(String uid) async {
    final i = _queue.indexWhere((e) => e.uid == uid);
    if (i < 0) return;
    final item = _queue.removeAt(i);
    _finishCurrent(QueueStatus.skipped);
    _queue.insert(0, item);
    await _playNext();
  }

  // ------------------------------------------------------ phát & chuyển bài

  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _current = null;
      _playerState = PlayerState.stopped;
      _basePosition = 0;
      _duration = 0;
      await target.stop();
      _persist();
      notifyListeners();
      return;
    }

    _markActivity();
    final item = _queue.removeAt(0);
    _current = item.copyWith(status: QueueStatus.playing, playedAt: DateTime.now());
    _basePosition = 0;
    _basePositionAt = DateTime.now();
    _duration = item.song.durationSec.toDouble();
    _playerState = PlayerState.buffering;
    _adSkippable = false;
    _isAd = false;
    _outsideVideoId = null;

    await _loadIntoTarget(item.song);
    _persist();
    notifyListeners();
  }

  Future<void> _loadIntoTarget(Song song) async {
    final now = DateTime.now();
    _guard.markLoaded(now);
    _guard.markAdvanced(now);
    await target.load(song);
    await target.setVolume(_settings.volume);
  }

  void _finishCurrent(QueueStatus status, {String? note}) {
    final item = _current;
    if (item == null) return;
    _pushHistory(item.copyWith(
      status: status,
      playedAt: item.playedAt ?? DateTime.now(),
      note: note,
    ));
    _current = null;
  }

  void _pushHistory(QueueItem item) {
    _history.insert(0, item);
    if (_history.length > historyLimit) {
      _history.removeRange(historyLimit, _history.length);
    }
  }

  // --------------------------------------------------- sự kiện từ bộ phát

  void _onPlaybackUpdate(PlaybackUpdate u, PlaybackMode source) {
    // Bỏ sự kiện đến muộn từ bộ phát không còn được dùng.
    if (source != mode) return;

    if (u.isEmbedBlocked) {
      _handleEmbedBlocked(u.videoId);
      return;
    }

    _isAd = u.isAd;
    _adSkippable = u.adSkippable;

    // Quảng cáo không được tính là hết bài (mục 12).
    if (u.isAd) {
      notifyListeners();
      return;
    }

    final currentVideoId = _current?.song.videoId;
    if (u.videoId != null && currentVideoId != null) {
      if (u.videoId != currentVideoId) {
        // Ai đó dùng remote TV / app YouTube chọn bài khác: không giành lại.
        if (_outsideVideoId != u.videoId) {
          _outsideVideoId = u.videoId;
          _toast('TV đang phát bài ngoài hàng chờ', isError: true);
        }
        notifyListeners();
        return;
      }
      _outsideVideoId = null;
    }

    _playerState = u.state;
    _basePosition = u.position;
    _basePositionAt = DateTime.now();
    if (u.duration > 0) _duration = u.duration;

    if (u.state == PlayerState.ended) {
      final decision = _guard.evaluate(
        now: DateTime.now(),
        position: u.position,
        duration: u.duration,
      );
      if (decision.shouldAdvance) {
        _finishCurrent(QueueStatus.played);
        _playNext();
        return;
      }
      debugPrint('Bỏ qua sự kiện hết bài: ${decision.reason}');
    }

    notifyListeners();
  }

  /// Video bị chặn nhúng (lỗi 101/150) ở chế độ phát trên điện thoại: bỏ qua,
  /// báo cho chủ phòng và người đã chọn bài (mục 8).
  void _handleEmbedBlocked(String? videoId) {
    final item = _current;
    if (item == null || (videoId != null && item.song.videoId != videoId)) {
      return;
    }
    const message = 'Bài này không phát được ngoài YouTube, đã bỏ qua';
    _finishCurrent(QueueStatus.skipped, note: message);
    _toast('"${item.song.title}": $message', isError: true);
    if (!item.requestedBy.isHost) {
      _toast(
        '"${item.song.title}": $message',
        guestId: item.requestedBy.guestId,
        isError: true,
      );
    }
    _playNext();
  }

  /// Gắn thông tin "không nhúng được" nếu đã biết từ lần phát trước.
  Song _markEmbedInfo(Song song) =>
      _phoneTarget.blockedVideoIds.contains(song.videoId)
          ? song.copyWith(embeddable: false)
          : song;

  // ------------------------------------------------------------------- phụ

  void _toast(String message, {String? guestId, bool isError = false}) {
    if (_toasts.isClosed) return;
    _toasts.add(RoomToast(message, guestId: guestId, isError: isError));
  }

  void _persist() => _storage.saveRoom(RoomSnapshot(
        current: _current,
        queue: _queue,
        pending: _pending,
        history: _history,
        guests: _guests.values.toList(),
        sessionStartedAt: _sessionStartedAt,
        lastActivityAt: _lastActivityAt,
        tvOfflineSince: _tvOfflineSince,
      ));

  /// Trạng thái đầy đủ gửi cho khách (`/api/state` và WebSocket `state`).
  Map<String, dynamic> toStateJson({String? forGuestId}) => {
        'mode': mode.wire,
        'roomCode': _roomCode,
        'tv': {
          'status': tvLink.state.name,
          'statusText': tvLink.description,
          'name': tvLink.label,
          'volume': _settings.volume,
          'playerState': _playerState.code,
          'position': position,
          'duration': _duration,
          'isAd': _isAd,
          'adSkippable': _adSkippable,
          'outsideVideoId': _outsideVideoId,
        },
        'current': _current?.toJson(),
        'upNext': upNext?.toJson(),
        'queue': _queue
            .map((i) => {...i.toJson(), 'position': queuePositionOf(i.uid)})
            .toList(),
        'pendingCount': _pending.length,
        'history': _history
            .where((i) => i.status == QueueStatus.played)
            .take(historyLimit)
            .map((e) => e.toJson())
            .toList(),
        'settings': {
          'autoApprove': _settings.autoApprove,
          'guestControl': _settings.guestControl,
          'maxPendingPerGuest': _settings.maxPendingPerGuest,
          'preferKaraoke': _settings.preferKaraoke,
        },
        if (forGuestId != null)
          'mine': itemsOf(forGuestId)
              .map((i) => {
                    ...i.toJson(),
                    'position': queuePositionOf(i.uid),
                  })
              .toList(),
      };
}

class RoomException implements Exception {
  RoomException(this.message);

  final String message;

  @override
  String toString() => message;
}
