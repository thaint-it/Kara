import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'browser_channel.dart';
import 'lounge_events.dart';

/// Trạng thái ghép nối / kết nối với TV, hiện trực tiếp lên app chủ phòng
/// (mục 7.5 của đặc tả).
enum TvLinkState {
  /// Chưa ghép TV nào.
  unpaired,

  /// Đang làm mới token / mở phiên.
  connecting,

  /// Đã mở phiên, đang nghe sự kiện.
  connected,

  /// Từng ghép nhưng hiện mất kết nối, sẽ tự thử lại.
  disconnected,
}

@immutable
class TvLink {
  const TvLink({
    required this.state,
    this.screenName,
    this.deviceName,
    this.error,
  });

  const TvLink.unpaired() : this._(TvLinkState.unpaired);

  const TvLink._(this.state)
      : screenName = null,
        deviceName = null,
        error = null;

  final TvLinkState state;
  final String? screenName;
  final String? deviceName;
  final String? error;

  /// Tên hiển thị của TV: ưu tiên tên người dùng đặt trên TV.
  String get label => screenName ?? deviceName ?? 'TV';

  String get description => switch (state) {
        TvLinkState.unpaired => 'Chưa ghép',
        TvLinkState.connecting => 'Đang kết nối…',
        TvLinkState.connected => 'Đã kết nối – $label',
        TvLinkState.disconnected => error == null
            ? 'Mất kết nối – đang thử lại'
            : 'Mất kết nối – $error',
      };

  TvLink copyWith({
    TvLinkState? state,
    String? screenName,
    String? deviceName,
    String? error,
    bool clearError = false,
  }) =>
      TvLink(
        state: state ?? this.state,
        screenName: screenName ?? this.screenName,
        deviceName: deviceName ?? this.deviceName,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Thông tin đăng nhập Lounge cần lưu lại để lần sau tự kết nối.
@immutable
class TvAuth {
  const TvAuth({required this.screenId, this.loungeToken, this.screenName});

  final String screenId;
  final String? loungeToken;
  final String? screenName;

  Map<String, dynamic> toJson() => {
        'screenId': screenId,
        'loungeToken': loungeToken,
        'screenName': screenName,
      };

  static TvAuth? fromJson(Map<String, dynamic>? json) {
    final id = json?['screenId'] as String?;
    if (id == null || id.isEmpty) return null;
    return TvAuth(
      screenId: id,
      loungeToken: json!['loungeToken'] as String?,
      screenName: json['screenName'] as String?,
    );
  }
}

/// Điều khiển app YouTube trên Smart TV qua YouTube Lounge API.
///
/// ⚠️ API không chính thức (mục 7 + mục 13 của đặc tả): logic được port từ
/// thư viện Python `pyytlounge` v3.x. Mọi chỗ phụ thuộc giao thức nằm gọn
/// trong file này để khi YouTube đổi thì chỉ phải sửa một nơi.
class TvController {
  TvController({
    required this.deviceName,
    this.onAuthChanged,
    Duration retryDelay = const Duration(seconds: 5),
  }) : _retryDelay = retryDelay;

  static const _apiBase = 'https://www.youtube.com/api/lounge';

  /// Tên hiện lên trên TV khi kết nối.
  final String deviceName;

  /// Gọi khi `screenId` / `loungeToken` thay đổi để lớp trên lưu xuống máy.
  final void Function(TvAuth? auth)? onAuthChanged;

  final Duration _retryDelay;

  final ValueNotifier<TvLink> link = ValueNotifier(const TvLink.unpaired());
  final _events = StreamController<LoungeEvent>.broadcast();

  Stream<LoungeEvent> get events => _events.stream;

  TvAuth? _auth;
  String? _sid;
  String? _gsession;
  String? _lastEventId;
  int _commandOffset = 1;

  final _client = http.Client();
  http.Client? _subscribeClient;
  Future<void>? _loop;
  bool _running = false;
  Completer<void>? _wakeUp;

  bool get isPaired => _auth != null;
  bool get isLinked => _auth?.loungeToken != null;
  bool get isConnected => _sid != null && _gsession != null;
  String? get screenId => _auth?.screenId;

  // ---------------------------------------------------------------- vòng đời

  /// Nạp token đã lưu (nếu có) rồi bật vòng lặp tự kết nối.
  void start({TvAuth? auth}) {
    if (auth != null) _setAuth(auth, persist: false);
    if (_running) {
      _wake();
      return;
    }
    _running = true;
    _loop = _runLoop();
  }

  Future<void> stop() async {
    _running = false;
    _wake();
    _subscribeClient?.close();
    _subscribeClient = null;
    await _loop;
    _loop = null;
  }

  void dispose() {
    _running = false;
    _wake();
    _subscribeClient?.close();
    _client.close();
    _events.close();
    link.dispose();
  }

  /// "Quên TV này" – xoá token, dừng kết nối.
  void forget() {
    _connectionLost();
    _setAuth(null);
    link.value = const TvLink.unpaired();
    _wake();
  }

  void _setAuth(TvAuth? auth, {bool persist = true}) {
    _auth = auth;
    if (persist) onAuthChanged?.call(auth);
  }

  void _wake() {
    final w = _wakeUp;
    _wakeUp = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _sleep(Duration d) async {
    final w = Completer<void>();
    _wakeUp = w;
    await Future.any([w.future, Future<void>.delayed(d)]);
    _wakeUp = null;
  }

  Future<void> _runLoop() async {
    while (_running) {
      if (_auth == null) {
        link.value = const TvLink.unpaired();
        await _sleep(const Duration(hours: 1));
        continue;
      }

      link.value = link.value.copyWith(
        state: TvLinkState.connecting,
        screenName: _auth?.screenName,
        clearError: true,
      );

      try {
        if (!isLinked && !await refreshAuth()) {
          await _fail('Không làm mới được token');
          continue;
        }
        if (!await _openSession()) {
          await _fail('TV chưa bật hoặc không nhận kết nối');
          continue;
        }

        link.value = link.value.copyWith(
          state: TvLinkState.connected,
          screenName: _auth?.screenName,
          clearError: true,
        );

        // Tắt tự phát video gợi ý ngay sau khi kết nối (mục 7.2) để khi hết
        // bài TV không nhảy sang video YouTube đề xuất.
        await setAutoplayEnabled(false);
        await getNowPlaying();

        await _subscribe();
      } catch (e, st) {
        debugPrint('TvController lỗi: $e\n$st');
        await _fail(_shortError(e));
        continue;
      }

      _connectionLost();
      if (!_running) break;
      link.value = link.value.copyWith(state: TvLinkState.disconnected);
      await _sleep(_retryDelay);
    }
  }

  Future<void> _fail(String message) async {
    _connectionLost();
    if (!_running) return;
    link.value = link.value.copyWith(
      state: TvLinkState.disconnected,
      error: message,
    );
    await _sleep(_retryDelay);
  }

  void _connectionLost() {
    _sid = null;
    _gsession = null;
    _lastEventId = null;
    _subscribeClient?.close();
    _subscribeClient = null;
  }

  // -------------------------------------------------------------- ghép nối

  /// Ghép nối bằng mã 12 số lấy từ *YouTube trên TV → Cài đặt → Liên kết với
  /// TV bằng mã*.
  Future<bool> pairWithCode(String pairingCode) async {
    final code = pairingCode.replaceAll(RegExp(r'\s+'), '');
    final res = await _client.post(
      Uri.parse('$_apiBase/pairing/get_screen'),
      body: {'pairing_code': code},
    );
    if (res.statusCode != 200) {
      throw TvPairingException('Mã không đúng hoặc đã hết hạn');
    }
    final screen = (jsonDecode(res.body) as Map<String, dynamic>)['screen']
        as Map<String, dynamic>;
    _setAuth(TvAuth(
      screenId: screen['screenId'] as String,
      loungeToken: screen['loungeToken'] as String?,
      screenName: screen['name'] as String?,
    ));
    _connectionLost();
    start();
    _wake();
    return isLinked;
  }

  /// Làm mới `loungeToken` từ `screenId` đã lưu.
  Future<bool> refreshAuth() async {
    final auth = _auth;
    if (auth == null) return false;
    final res = await _client.post(
      Uri.parse('$_apiBase/pairing/get_lounge_token_batch'),
      body: {'screen_ids': auth.screenId},
    );
    if (res.statusCode != 200) return false;
    final screens =
        (jsonDecode(res.body) as Map<String, dynamic>)['screens'] as List;
    if (screens.isEmpty) return false;
    final screen = screens.first as Map<String, dynamic>;
    _setAuth(TvAuth(
      screenId: screen['screenId'] as String? ?? auth.screenId,
      loungeToken: screen['loungeToken'] as String?,
      screenName: auth.screenName,
    ));
    return isLinked;
  }

  /// Hỏi YouTube xem TV có đang online không.
  Future<bool> isScreenAvailable() async {
    final token = _auth?.loungeToken;
    if (token == null) return false;
    final res = await _client.post(
      Uri.parse('$_apiBase/pairing/get_screen_availability'),
      body: {'lounge_token': token},
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final screens = data['screens'] as List?;
    if (screens == null || screens.isEmpty) return false;
    return (screens.first as Map<String, dynamic>)['status'] == 'online';
  }

  // ------------------------------------------------------------- phiên /bc

  Future<bool> _openSession() async {
    final auth = _auth!;
    final body = {
      'app': 'web',
      'mdx-version': '3',
      'name': deviceName,
      'id': auth.screenId,
      'device': 'REMOTE_CONTROL',
      'capabilities': 'que,dsdtr,atp,vsp',
      'magnaKey': 'cloudPairedDevice',
      'ui': 'false',
      'deviceContext':
          'user_agent=dunno&window_width_points=&window_height_points=&os_name=android&ms=',
      'theme': 'cl',
      'loungeIdToken': auth.loungeToken!,
    };

    final res = await _client.post(
      Uri.parse(
        '$_apiBase/bc/bind?RID=1&VER=8&CVER=1&auth_failure_option=send_error',
      ),
      body: body,
    );

    if (res.statusCode == 401) {
      _loungeTokenExpired();
      return false;
    }
    if (res.statusCode != 200) return false;

    final parser = BrowserChannelParser();
    for (final batch in parser.push(utf8.decode(res.bodyBytes))) {
      _processEvents(batch);
    }
    _commandOffset = 1;
    return isConnected;
  }

  /// Giữ một request GET dài để nhận sự kiện từ TV. Hàm này chỉ trả về khi
  /// phiên kết thúc (TV tắt, token hết hạn, hoặc [stop] được gọi).
  Future<void> _subscribe() async {
    final client = http.Client();
    _subscribeClient = client;

    final uri = Uri.parse('$_apiBase/bc/bind').replace(
      queryParameters: {
        ..._commonParams(),
        'RID': 'rpc',
        'CI': '0',
        'TYPE': 'xmlhttp',
      },
    );

    try {
      final res = await client.send(http.Request('GET', uri));
      if (!_handleSessionResult(res.statusCode, res.reasonPhrase ?? '')) {
        return;
      }
      if (res.statusCode != 200) {
        link.value = link.value.copyWith(error: 'HTTP ${res.statusCode}');
        return;
      }

      final parser = BrowserChannelParser();
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        for (final batch in parser.push(chunk)) {
          _processEvents(batch);
        }
        if (!isConnected || !_running) break;
      }
    } on http.ClientException {
      // Request bị đóng (stop / mất mạng) – vòng lặp ngoài sẽ thử lại.
    } finally {
      if (identical(_subscribeClient, client)) _subscribeClient = null;
      client.close();
    }
  }

  Map<String, String> _commonParams() {
    final auth = _auth!;
    return {
      'name': deviceName,
      'loungeIdToken': auth.loungeToken!,
      if (_sid != null) 'SID': _sid!,
      if (_lastEventId != null) 'AID': _lastEventId!,
      if (_gsession != null) 'gsessionid': _gsession!,
      'device': 'REMOTE_CONTROL',
      'app': 'youtube-desktop',
      'VER': '8',
      'v': '2',
    };
  }

  bool _handleSessionResult(int status, String text) {
    if (status == 400 && text.contains('Unknown SID')) {
      _connectionLost();
      return false;
    }
    if (status == 410) {
      _connectionLost();
      return false;
    }
    if (status == 401) {
      _connectionLost();
      _loungeTokenExpired();
      return false;
    }
    return true;
  }

  void _loungeTokenExpired() {
    final auth = _auth;
    if (auth == null) return;
    _setAuth(TvAuth(screenId: auth.screenId, screenName: auth.screenName));
  }

  // ------------------------------------------------------------------ lệnh

  Future<bool> _command(String command, [Map<String, Object?>? params]) async {
    if (!isConnected) return false;

    final body = <String, String>{
      'count': '1',
      'ofs': '$_commandOffset',
      'req0__sc': command,
    };
    params?.forEach((k, v) {
      if (v != null) body['req0_$k'] = '$v';
    });

    _commandOffset++;
    final uri = Uri.parse('$_apiBase/bc/bind').replace(
      queryParameters: {..._commonParams(), 'RID': '$_commandOffset'},
    );

    try {
      final res = await _client.post(uri, body: body);
      if (!_handleSessionResult(res.statusCode, res.body)) return false;
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('Gửi lệnh "$command" thất bại: $e');
      return false;
    }
  }

  /// Phát một video – đặt hẳn playlist mới nên bài đang phát bị thay thế.
  Future<bool> playVideo(String videoId) =>
      _command('setPlaylist', {'videoId': videoId});

  Future<bool> play() => _command('play');

  Future<bool> pause() => _command('pause');

  Future<bool> next() => _command('next');

  Future<bool> previous() => _command('previous');

  Future<bool> seekTo(double seconds) =>
      _command('seekTo', {'newTime': seconds});

  Future<bool> setVolume(int volume) =>
      _command('setVolume', {'volume': volume.clamp(0, 100)});

  Future<bool> skipAd() => _command('skipAd');

  Future<bool> setAutoplayEnabled(bool enabled) => _command(
        'setAutoplayMode',
        {'autoplayMode': enabled ? 'ENABLED' : 'DISABLED'},
      );

  Future<bool> getNowPlaying() => _command('getNowPlaying');

  Future<bool> disconnectSession() async {
    if (!isConnected) return false;
    final uri = Uri.parse('$_apiBase/bc/bind').replace(
      queryParameters: {
        ..._commonParams(),
        'CVER': '1',
        'RID': '$_commandOffset',
        'auth_failure_option': 'send_error',
      },
    );
    final res = await _client.post(uri, body: {
      'ui': '',
      'TYPE': 'terminate',
      'clientDisconnectReason':
          'MDX_SESSION_DISCONNECT_REASON_DISCONNECTED_BY_USER',
    });
    _connectionLost();
    return res.statusCode == 200;
  }

  // ------------------------------------------------------------- sự kiện

  void _processEvents(List<dynamic> batch) {
    for (final entry in batch) {
      if (entry is! List || entry.length < 2) continue;
      final payload = entry[1];
      if (payload is! List || payload.isEmpty) continue;

      final type = '${payload[0]}';
      final args = payload.sublist(1);

      switch (type) {
        case 'c':
          _sid = args.isEmpty ? null : '${args[0]}';
        case 'S':
          _gsession = args.isEmpty ? null : '${args[0]}';
        default:
          _emit(type, args);
      }
    }

    final last = batch.isEmpty ? null : batch.last;
    if (last is List && last.isNotEmpty) _lastEventId = '${last[0]}';
  }

  void _emit(String type, List<dynamic> args) {
    Map<String, dynamic> data() =>
        args.isNotEmpty && args.first is Map<String, dynamic>
            ? args.first as Map<String, dynamic>
            : const {};

    switch (type) {
      case 'nowPlaying':
        _events.add(NowPlayingEvent.fromJson(data()));
      case 'onStateChange':
        _events.add(PlaybackStateEvent.fromJson(data()));
      case 'onVolumeChanged':
        _events.add(VolumeChangedEvent.fromJson(data()));
      case 'onAdStateChange':
      case 'adPlaying':
        _events.add(AdStateEvent.fromJson(data()));
      case 'onAutoplayModeChanged':
        _events.add(AutoplayModeEvent.fromJson(data()));
      case 'loungeStatus':
        _handleLoungeStatus(data());
      case 'loungeScreenDisconnected':
        _events.add(ScreenDisconnectedEvent(reason: data()['reason'] as String?));
        _connectionLost();
        _loungeTokenExpired();
      case 'noop':
        break;
      default:
        _events.add(LoungeRawEvent(type, args));
    }
  }

  void _handleLoungeStatus(Map<String, dynamic> data) {
    final rawDevices = data['devices'];
    if (rawDevices is! String) return;
    final devices = jsonDecode(rawDevices) as List;
    for (final d in devices) {
      if (d is! Map<String, dynamic>) continue;
      if (d['type'] != 'LOUNGE_SCREEN') continue;

      final screenName = d['name'] as String?;
      String? deviceName;
      final rawInfo = d['deviceInfo'];
      if (rawInfo is String && rawInfo.isNotEmpty) {
        final info = jsonDecode(rawInfo);
        if (info is Map<String, dynamic>) {
          deviceName = [info['brand'], info['model']]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' ');
          if (deviceName.isEmpty) deviceName = null;
        }
      }

      final auth = _auth;
      if (auth != null && screenName != null && screenName != auth.screenName) {
        _setAuth(TvAuth(
          screenId: auth.screenId,
          loungeToken: auth.loungeToken,
          screenName: screenName,
        ));
      }
      link.value = link.value.copyWith(
        screenName: screenName,
        deviceName: deviceName,
      );
      _events.add(LoungeStatusEvent(
        screenName: screenName,
        deviceName: deviceName,
      ));
      break;
    }
  }

  static String _shortError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }
}

class TvPairingException implements Exception {
  TvPairingException(this.message);

  final String message;

  @override
  String toString() => message;
}
