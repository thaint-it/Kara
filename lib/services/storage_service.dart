import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lounge/tv_controller.dart';
import '../models/guest.dart';
import '../models/queue_item.dart';
import '../models/room_settings.dart';

/// Lưu cài đặt + token TV vào `shared_preferences`, còn hàng chờ / lịch sử /
/// danh sách khách vào một file JSON (dữ liệu nhiều và ghi thường xuyên).
class StorageService {
  StorageService._(this._prefs, this._roomFile);

  static const _kTvAuth = 'tv_auth';
  static const _kSettings = 'room_settings';
  static const _kRoomCode = 'room_code';

  final SharedPreferences _prefs;
  final File _roomFile;

  /// Gộp nhiều lần ghi liên tiếp thành một để không chặn UI.
  Timer? _flushTimer;
  Map<String, dynamic>? _pendingRoom;

  static Future<StorageService> open() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    return StorageService._(prefs, File('${dir.path}/kara_room.json'));
  }

  // --------------------------------------------------------------- cài đặt

  RoomSettings loadSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null) return const RoomSettings();
    try {
      return RoomSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const RoomSettings();
    }
  }

  Future<void> saveSettings(RoomSettings settings) =>
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));

  // ------------------------------------------------------------- token TV

  TvAuth? loadTvAuth() {
    final raw = _prefs.getString(_kTvAuth);
    if (raw == null) return null;
    try {
      return TvAuth.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTvAuth(TvAuth? auth) => auth == null
      ? _prefs.remove(_kTvAuth)
      : _prefs.setString(_kTvAuth, jsonEncode(auth.toJson()));

  // ------------------------------------------------------------- mã phòng

  /// Mã phòng 4 số, giữ nguyên giữa các lần mở app để QR cũ còn dùng được.
  String roomCode() {
    final existing = _prefs.getString(_kRoomCode);
    if (existing != null && existing.length == 4) return existing;
    final code = (1000 + DateTime.now().microsecondsSinceEpoch % 9000).toString();
    _prefs.setString(_kRoomCode, code);
    return code;
  }

  Future<String> regenerateRoomCode() async {
    final code = (1000 + DateTime.now().microsecondsSinceEpoch % 9000).toString();
    await _prefs.setString(_kRoomCode, code);
    return code;
  }

  // ----------------------------------------------- hàng chờ / lịch sử / khách

  Future<RoomSnapshot> loadRoom() async {
    try {
      if (!await _roomFile.exists()) return RoomSnapshot.empty();
      final json =
          jsonDecode(await _roomFile.readAsString()) as Map<String, dynamic>;
      return RoomSnapshot.fromJson(json);
    } catch (e) {
      debugPrint('Không đọc được hàng chờ đã lưu: $e');
      return RoomSnapshot.empty();
    }
  }

  /// Ghi có hoãn 500 ms – hàng chờ thay đổi liên tục khi kéo thả.
  void saveRoom(RoomSnapshot snapshot) {
    _pendingRoom = snapshot.toJson();
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() async {
    final data = _pendingRoom;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingRoom = null;
    if (data == null) return;
    try {
      await _roomFile.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Không lưu được hàng chờ: $e');
    }
  }
}

/// Phần trạng thái phòng cần sống sót qua việc tắt/mở app.
@immutable
class RoomSnapshot {
  const RoomSnapshot({
    required this.current,
    required this.queue,
    required this.pending,
    required this.history,
    required this.guests,
    this.sessionStartedAt,
    this.lastActivityAt,
    this.tvOfflineSince,
  });

  factory RoomSnapshot.empty() => const RoomSnapshot(
        current: null,
        queue: [],
        pending: [],
        history: [],
        guests: [],
      );

  final QueueItem? current;
  final List<QueueItem> queue;
  final List<QueueItem> pending;
  final List<QueueItem> history;
  final List<Guest> guests;

  /// Mốc bắt đầu buổi hát đang diễn ra.
  final DateTime? sessionStartedAt;

  /// Lần cuối có bài được phát hoặc có người gửi yêu cầu. Dùng để tự kết thúc
  /// buổi hát khi không ai dùng nữa.
  final DateTime? lastActivityAt;

  /// Lần TV bắt đầu mất kết nối. Lưu lại để tắt/mở app không làm đồng hồ này
  /// chạy lại từ đầu.
  final DateTime? tvOfflineSince;

  Map<String, dynamic> toJson() => {
        if (current != null) 'current': current!.toJson(),
        'queue': queue.map((e) => e.toJson()).toList(),
        'pending': pending.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
        'guests': guests.map((e) => e.toJson()).toList(),
        if (sessionStartedAt != null)
          'sessionStartedAt': sessionStartedAt!.toIso8601String(),
        if (lastActivityAt != null)
          'lastActivityAt': lastActivityAt!.toIso8601String(),
        if (tvOfflineSince != null)
          'tvOfflineSince': tvOfflineSince!.toIso8601String(),
      };

  factory RoomSnapshot.fromJson(Map<String, dynamic> j) => RoomSnapshot(
        current: j['current'] == null
            ? null
            : QueueItem.fromJson(j['current'] as Map<String, dynamic>),
        queue: _items(j['queue']),
        pending: _items(j['pending']),
        history: _items(j['history']),
        guests: (j['guests'] as List? ?? [])
            .map((e) => Guest.fromJson(e as Map<String, dynamic>))
            .toList(),
        sessionStartedAt: _date(j['sessionStartedAt']),
        lastActivityAt: _date(j['lastActivityAt']),
        tvOfflineSince: _date(j['tvOfflineSince']),
      );

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  static List<QueueItem> _items(Object? raw) => (raw as List? ?? [])
      .map((e) => QueueItem.fromJson(e as Map<String, dynamic>))
      .toList();
}
