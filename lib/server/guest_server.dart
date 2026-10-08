import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/room_controller.dart';
import '../models/song.dart';
import 'rate_limiter.dart';

/// Web server nhúng trong app chủ phòng: phục vụ trang web cho khách, API tìm
/// bài / gửi yêu cầu, và WebSocket đẩy trạng thái về (mục 9).
class GuestServer {
  GuestServer(this.room);

  static const defaultPort = 8080;

  final RoomController room;

  HttpServer? _httpServer;
  final _clients = <_GuestClient>[];
  final _requestLimiter = RateLimiter();

  Timer? _progressTimer;
  Timer? _stateDebounce;
  Timer? _addressTimer;
  StreamSubscription<RoomToast>? _toastSub;

  Uri? _uri;

  Uri? get uri => _uri;

  bool get isRunning => _httpServer != null;

  // ------------------------------------------------------------- vòng đời

  Future<Uri> start({int port = defaultPort}) async {
    if (_httpServer != null) return _uri!;

    final handler = const Pipeline()
        .addMiddleware(_noCache)
        .addHandler(_buildRouter().call);

    var server = await _bind(handler, port);
    _httpServer = server;

    final ip = await _localIp() ?? server.address.address;
    _uri = Uri(scheme: 'http', host: ip, port: server.port);

    room.addListener(_onRoomChanged);
    _toastSub = room.toasts.listen(_sendToast);
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (room.isPlaying) _broadcastProgress();
    });
    // Đổi WiFi / bật hotspot làm IP thay đổi; mã QR phải đổi theo (mục 12).
    _addressTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _refreshAddress());

    debugPrint('Web server khách đang chạy tại $_uri');
    return _uri!;
  }

  Future<void> _refreshAddress() async {
    final server = _httpServer;
    if (server == null) return;

    final ip = await _localIp();
    if (ip == null || ip == _uri?.host) return;

    _uri = Uri(scheme: 'http', host: ip, port: server.port);
    debugPrint('IP đổi, địa chỉ khách giờ là $_uri');
    room.attachServer(_uri!);
  }

  /// Thử cổng mặc định trước; nếu bị chiếm thì để hệ thống chọn cổng trống.
  Future<HttpServer> _bind(Handler handler, int port) async {
    try {
      return await shelf_io.serve(handler, InternetAddress.anyIPv4, port,
          shared: true);
    } on SocketException {
      debugPrint('Cổng $port đang bị dùng, chuyển sang cổng khác');
      return shelf_io.serve(handler, InternetAddress.anyIPv4, 0, shared: true);
    }
  }

  Future<void> stop() async {
    _progressTimer?.cancel();
    _stateDebounce?.cancel();
    _addressTimer?.cancel();
    await _toastSub?.cancel();
    room.removeListener(_onRoomChanged);
    for (final c in _clients.toList()) {
      c.close();
    }
    _clients.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
    _uri = null;
  }

  // -------------------------------------------------------------- định tuyến

  Router _buildRouter() {
    final router = Router()
      ..get('/ws', webSocketHandler(_onWebSocket, pingInterval: const Duration(seconds: 20)))
      ..get('/api/state', _handleState)
      ..get('/api/suggest', _handleSuggest)
      ..get('/api/search', _handleSearch)
      ..get('/api/home', _handleHome)
      ..post('/api/request', _handleRequest)
      ..post('/api/request/cancel', _handleCancel)
      ..post('/api/control', _handleControl)
      ..get('/player', (Request r) => _asset('assets/web/player.html', 'text/html'))
      ..get('/', (Request r) => _asset('assets/web/index.html', 'text/html'))
      ..get('/<file|.*>', _handleStatic);
    return router;
  }

  static Middleware get _noCache => (innerHandler) => (request) async {
        final response = await innerHandler(request);
        return response.change(headers: {
          'cache-control': 'no-store',
          // Trang khách và API cùng origin nên không cần CORS rộng; chỉ mở cho
          // trường hợp khách mở qua IP khác (hotspot đổi dải địa chỉ).
          'access-control-allow-origin': '*',
        });
      };

  // ----------------------------------------------------------------- tĩnh

  static const _mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.ico': 'image/x-icon',
    '.webmanifest': 'application/manifest+json',
  };

  Future<Response> _handleStatic(Request request) {
    final file = request.params['file'] ?? '';
    if (file.isEmpty || file.contains('..')) {
      return Future.value(_notFound());
    }
    final ext = file.contains('.') ? file.substring(file.lastIndexOf('.')) : '';
    return _asset('assets/web/$file', _mimeTypes[ext] ?? 'application/octet-stream');
  }

  Future<Response> _asset(String key, String contentType) async {
    try {
      final data = await rootBundle.load(key);
      return Response.ok(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        headers: {'content-type': contentType},
      );
    } catch (_) {
      return _notFound();
    }
  }

  static Response _notFound() =>
      Response.notFound('Không tìm thấy', headers: {'content-type': 'text/plain; charset=utf-8'});

  // ------------------------------------------------------------------- API

  Response _json(Object? body, {int status = 200}) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Response _error(String message, {int status = 400}) =>
      _json({'ok': false, 'error': message}, status: status);

  Future<Response> _handleState(Request request) async {
    final guestId = request.url.queryParameters['guestId'];
    final name = request.url.queryParameters['name'];
    if (guestId != null && guestId.isNotEmpty) {
      room.upsertGuest(guestId, name ?? 'Khách');
    }
    return _json(room.toStateJson(forGuestId: guestId));
  }

  Future<Response> _handleSuggest(Request request) async {
    final q = request.url.queryParameters['q'] ?? '';
    return _json({'suggestions': await room.youtube.suggest(q)});
  }

  Future<Response> _handleSearch(Request request) async {
    final p = request.url.queryParameters;
    final q = p['q'] ?? '';
    if (q.trim().isEmpty) return _json({'results': const []});

    final page = int.tryParse(p['page'] ?? '0') ?? 0;
    final karaoke = switch (p['karaoke']) {
      '1' || 'true' => true,
      '0' || 'false' => false,
      _ => room.settings.preferKaraoke,
    };

    try {
      final results = await room.youtube.search(q, page: page, preferKaraoke: karaoke);
      final blocked = room.phoneTarget.blockedVideoIds;
      return _json({
        'page': page,
        'results': results
            .map((s) => {
                  ...s.toJson(),
                  'inQueue': room.isDuplicate(s.videoId),
                  if (blocked.contains(s.videoId)) 'embeddable': false,
                })
            .toList(),
      });
    } catch (e) {
      debugPrint('Tìm kiếm cho khách thất bại: $e');
      return _error('Không tìm được. Kiểm tra Internet rồi thử lại.',
          status: 503);
    }
  }

  /// Màn hình tìm kiếm khi khách chưa gõ gì: bài vừa hát trong phòng + bài
  /// đề xuất, cho người không nhớ tên bài chọn khi thấy nó hiện ra.
  Future<Response> _handleHome(Request request) async {
    final karaoke = switch (request.url.queryParameters['karaoke']) {
      '1' || 'true' => true,
      '0' || 'false' => false,
      _ => room.settings.preferKaraoke,
    };
    Map<String, dynamic> withFlags(Song s) => {
          ...s.toJson(),
          'inQueue': room.isDuplicate(s.videoId),
          if (room.phoneTarget.blockedVideoIds.contains(s.videoId))
            'embeddable': false,
        };

    List<Song> recommended;
    try {
      recommended = await room.recommendations(preferKaraoke: karaoke);
    } catch (e) {
      debugPrint('Lấy bài đề xuất cho khách thất bại: $e');
      recommended = const [];
    }
    return _json({
      'recent': room.recentlySung().map(withFlags).toList(),
      'recommended': recommended.map(withFlags).toList(),
    });
  }

  Future<Response> _handleRequest(Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error('Dữ liệu không hợp lệ');
    if (!_checkRoomCode(body)) {
      return _error('Sai mã phòng, hãy quét lại mã QR', status: 403);
    }

    final guestId = (body['guestId'] as String?)?.trim() ?? '';
    final name = (body['name'] as String?)?.trim() ?? 'Khách';
    if (guestId.isEmpty) return _error('Thiếu guestId');

    if (!_requestLimiter.allow(guestId)) {
      final wait = _requestLimiter.retryAfterSeconds(guestId);
      return _error('Bạn gửi hơi nhanh, thử lại sau $wait giây', status: 429);
    }

    final songJson = body['song'];
    if (songJson is! Map<String, dynamic> || songJson['videoId'] is! String) {
      return _error('Thiếu thông tin bài hát');
    }

    try {
      final item = room.requestSong(
        song: Song.fromJson(songJson),
        guestId: guestId,
        guestName: name,
      );
      return _json({
        'ok': true,
        'item': {...item.toJson(), 'position': room.queuePositionOf(item.uid)},
      });
    } on RoomException catch (e) {
      return _error(e.message, status: 429);
    }
  }

  Future<Response> _handleCancel(Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error('Dữ liệu không hợp lệ');
    if (!_checkRoomCode(body)) return _error('Sai mã phòng', status: 403);

    final guestId = body['guestId'] as String? ?? '';
    final uid = body['uid'] as String? ?? '';
    final ok = room.cancelRequest(uid, guestId);
    return ok ? _json({'ok': true}) : _error('Yêu cầu đã được xử lý rồi');
  }

  Future<Response> _handleControl(Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error('Dữ liệu không hợp lệ');
    if (!_checkRoomCode(body)) return _error('Sai mã phòng', status: 403);
    if (!room.settings.guestControl) {
      return _error('Chủ phòng chưa cho khách điều khiển', status: 403);
    }

    switch (body['action']) {
      case 'next':
        await room.skip();
      case 'pause':
      case 'play':
      case 'toggle':
        await room.togglePlayPause();
      default:
        return _error('Lệnh không hợp lệ');
    }
    return _json({'ok': true});
  }

  bool _checkRoomCode(Map<String, dynamic> body) =>
      body['room'] == room.roomCode;

  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final text = await request.readAsString();
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- WebSocket

  void _onWebSocket(WebSocketChannel channel, String? _) {
    final client = _GuestClient(channel);
    _clients.add(client);

    channel.stream.listen(
      (raw) {
        final Map<String, dynamic> msg;
        try {
          msg = jsonDecode('$raw') as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        switch (msg['type']) {
          case 'hello':
            final guestId = (msg['guestId'] as String?)?.trim();
            if (guestId == null || guestId.isEmpty) return;
            client.guestId = guestId;
            room.upsertGuest(guestId, (msg['name'] as String?) ?? 'Khách');
            client.send({'type': 'state', ...room.toStateJson()});
            client.send({
              'type': 'request_update',
              'mine': _mineJson(guestId),
            });
          case 'ping':
            client.send({'type': 'pong'});
        }
      },
      onDone: () => _clients.remove(client),
      onError: (_) => _clients.remove(client),
      cancelOnError: true,
    );
  }

  void _onRoomChanged() {
    // Gộp các thay đổi dồn dập (kéo thả hàng chờ) thành một lần gửi.
    _stateDebounce?.cancel();
    _stateDebounce = Timer(const Duration(milliseconds: 150), _broadcastState);
  }

  void _broadcastState() {
    if (_clients.isEmpty) return;
    final shared = {'type': 'state', ...room.toStateJson()};
    for (final client in _clients.toList()) {
      client.send(shared);
      final guestId = client.guestId;
      if (guestId != null) {
        client.send({'type': 'request_update', 'mine': _mineJson(guestId)});
      }
    }
  }

  /// Gói tin nhẹ cho thanh tiến độ, gửi mỗi giây khi đang phát.
  void _broadcastProgress() {
    if (_clients.isEmpty) return;
    final msg = {
      'type': 'progress',
      'position': room.position,
      'duration': room.duration,
      'playerState': room.playerState.code,
    };
    for (final client in _clients.toList()) {
      client.send(msg);
    }
  }

  void _sendToast(RoomToast toast) {
    final msg = {
      'type': 'toast',
      'message': toast.message,
      'isError': toast.isError,
    };
    for (final client in _clients.toList()) {
      if (toast.guestId == null || client.guestId == toast.guestId) {
        client.send(msg);
      }
    }
  }

  List<Map<String, dynamic>> _mineJson(String guestId) => room
      .itemsOf(guestId)
      .map((i) => {...i.toJson(), 'position': room.queuePositionOf(i.uid)})
      .toList();

  // ------------------------------------------------------------- địa chỉ IP

  /// Địa chỉ IPv4 nội bộ của điện thoại chủ phòng.
  ///
  /// Dùng [NetworkInterface] trước vì không cần quyền gì; `network_info_plus`
  /// chỉ là phương án dự phòng (trên Android mới nó cần quyền vị trí).
  static Future<String?> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      // Ưu tiên wlan/en (WiFi) trước các giao diện ảo.
      interfaces.sort((a, b) => _interfaceRank(a.name) - _interfaceRank(b.name));
      for (final i in interfaces) {
        for (final addr in i.addresses) {
          if (_isPrivate(addr.address)) return addr.address;
        }
      }
    } catch (e) {
      debugPrint('Không liệt kê được network interface: $e');
    }

    try {
      return await NetworkInfo().getWifiIP();
    } catch (e) {
      debugPrint('Không lấy được IP WiFi: $e');
      return null;
    }
  }

  static int _interfaceRank(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('wlan') || n.startsWith('en')) return 0;
    if (n.startsWith('ap') || n.startsWith('swlan')) return 1;
    if (n.startsWith('eth') || n.startsWith('rndis')) return 2;
    return 3;
  }

  static bool _isPrivate(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
}

class _GuestClient {
  _GuestClient(this.channel);

  final WebSocketChannel channel;
  String? guestId;

  void send(Map<String, dynamic> message) {
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      // Kết nối đã đóng; danh sách client sẽ được dọn ở onDone.
    }
  }

  void close() {
    try {
      channel.sink.close();
    } catch (_) {}
  }
}
