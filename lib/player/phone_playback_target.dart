import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../lounge/lounge_events.dart';
import '../models/song.dart';
import 'playback_target.dart';

/// Phát ngay trên điện thoại chủ phòng bằng YouTube IFrame Player API trong
/// một WebView (mục 8 của đặc tả).
///
/// Trang phát được chính web server nhúng của app phục vụ tại `/player` – cần
/// một origin `http://` thật, vì YouTube IFrame API không chạy với
/// `about:blank` (đó là lý do không dùng `loadHtmlString`).
class PhonePlaybackTarget implements PlaybackTarget {
  PhonePlaybackTarget({required this.playerUrl});

  /// Ví dụ `http://127.0.0.1:8080/player`.
  final Uri Function() playerUrl;

  final _updates = StreamController<PlaybackUpdate>.broadcast();

  /// WebView sống độc lập với cây widget: tạo ở đây để chuyển qua lại giữa
  /// trình phát thu gọn và toàn màn hình mà không nạp lại video.
  WebViewController? _webView;
  WebViewController? get webView => _webView;

  /// `true` sau khi trang `/player` báo `ready`. Phải đặt lại về `false` mỗi
  /// lần [detach] vì trang sẽ được nạp lại từ đầu khi quay lại chế độ này.
  bool _pageReady = false;
  final _pendingJs = <String>[];

  String? _videoId;
  double _position = 0;
  double _duration = 0;
  PlayerState _state = PlayerState.stopped;
  int _volume = 100;

  /// Danh sách videoId đã biết là không nhúng được, để lọc trước khi phát.
  final _blockedVideoIds = <String>{};

  Set<String> get blockedVideoIds => UnmodifiableSetView(_blockedVideoIds);

  @override
  Stream<PlaybackUpdate> get updates => _updates.stream;

  @override
  bool get isReady => _pageReady;

  @override
  Future<void> attach() async {
    if (_webView != null) return;

    // Trên iPhone, hai thứ này phải đặt lúc tạo WebView chứ không sửa được
    // sau: `allowsInlineMediaPlayback` để video chạy ngay trong trang (nếu
    // không, iOS đẩy sang trình phát toàn màn hình của hệ thống và app mất
    // quyền điều khiển), và `mediaTypesRequiringUserAction` rỗng để không đòi
    // người dùng bấm — điều khiển nằm ở phía Flutter nên không có cú chạm nào
    // vào WebView.
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..addJavaScriptChannel('Kara', onMessageReceived: _onJsMessage);

    // Android có thiết lập tương đương, nhưng đặt được sau khi tạo.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
    }

    _webView = controller;
    await controller.loadRequest(playerUrl());
  }

  @override
  Future<void> detach() async {
    _webView?.loadRequest(Uri.parse('about:blank'));
    _webView = null;
    _pageReady = false;
    _pendingJs.clear();
    _videoId = null;
    _state = PlayerState.stopped;
  }

  @override
  Future<void> load(Song song, {double startAt = 0}) async {
    _videoId = song.videoId;
    _position = 0;
    _duration = song.durationSec.toDouble();
    await attach();
    await _js('kara.load(${jsonEncode(song.videoId)})');
    // [startAt] chỉ dùng khi lấy lại TV đã trả; trình phát trên điện thoại
    // không bao giờ bị "trả" nên luôn phát từ đầu.
  }

  @override
  Future<void> play() => _js('kara.play()');

  @override
  Future<void> pause() => _js('kara.pause()');

  @override
  Future<void> stop() async {
    _videoId = null;
    _state = PlayerState.stopped;
    await _js('kara.stop()');
  }

  @override
  Future<void> seek(double seconds) => _js('kara.seek($seconds)');

  /// IFrame Player API không có quảng cáo chèn giữa như app trên TV.
  @override
  Future<void> skipAd() async {}

  @override
  Future<void> setVolume(int volume) {
    _volume = volume.clamp(0, 100);
    return _js('kara.setVolume($_volume)');
  }

  void dispose() {
    _updates.close();
  }

  Future<void> _js(String code) async {
    final view = _webView;
    if (view == null) return;
    if (!_pageReady) {
      _pendingJs.add(code);
      return;
    }
    try {
      await view.runJavaScript(code);
    } catch (e) {
      debugPrint('Trình phát nhúng: lỗi chạy JS "$code": $e');
    }
  }

  void _onJsMessage(JavaScriptMessage message) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (msg['type']) {
      case 'ready':
        _pageReady = true;
        final queued = List<String>.from(_pendingJs);
        _pendingJs.clear();
        _js('kara.setVolume($_volume)');
        for (final code in queued) {
          _js(code);
        }

      case 'state':
        _state = PlayerState.parse(msg['state']);
        _position = _toDouble(msg['position']);
        final d = _toDouble(msg['duration']);
        if (d > 0) _duration = d;
        _videoId = (msg['videoId'] as String?) ?? _videoId;
        _emit();

      case 'error':
        final code = (msg['code'] as num?)?.toInt();
        final videoId = (msg['videoId'] as String?) ?? _videoId;
        if ((code == 101 || code == 150) && videoId != null) {
          _blockedVideoIds.add(videoId);
        }
        _updates.add(PlaybackUpdate(
          videoId: videoId,
          state: PlayerState.stopped,
          position: _position,
          duration: _duration,
          errorCode: code,
        ));

      default:
        return;
    }
  }

  void _emit() => _updates.add(PlaybackUpdate(
        videoId: _videoId,
        state: _state,
        position: _position,
        duration: _duration,
      ));

  static double _toDouble(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s) ?? 0,
        _ => 0,
      };
}
