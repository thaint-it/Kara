import 'dart:async';

import '../lounge/lounge_events.dart';
import '../lounge/tv_controller.dart';
import '../models/song.dart';
import 'playback_target.dart';

/// Phát qua app YouTube trên Smart TV.
class TvPlaybackTarget implements PlaybackTarget {
  TvPlaybackTarget(this.tv) {
    _sub = tv.events.listen(_onLoungeEvent);
  }

  final TvController tv;

  final _updates = StreamController<PlaybackUpdate>.broadcast();
  late final StreamSubscription<LoungeEvent> _sub;

  String? _videoId;
  double _position = 0;
  double _duration = 0;
  PlayerState _state = PlayerState.stopped;
  bool _adSkippable = false;
  bool _isAd = false;

  @override
  Stream<PlaybackUpdate> get updates => _updates.stream;

  @override
  bool get isReady => tv.isConnected;

  @override
  Future<void> attach() async {
    tv.start();
  }

  @override
  Future<void> detach() async {
    await tv.stop();
  }

  @override
  Future<void> load(Song song) async {
    _videoId = song.videoId;
    _position = 0;
    _duration = song.durationSec.toDouble();
    await tv.playVideo(song.videoId);
  }

  @override
  Future<void> play() => tv.play();

  @override
  Future<void> pause() => tv.pause();

  /// Lounge API không có lệnh "stop"; tạm dừng là cách gần nhất để TV không
  /// tự phát tiếp thứ gì khác.
  @override
  Future<void> stop() => tv.pause();

  @override
  Future<void> seek(double seconds) => tv.seekTo(seconds);

  @override
  Future<void> setVolume(int volume) => tv.setVolume(volume);

  @override
  Future<void> skipAd() => tv.skipAd();

  void dispose() {
    _sub.cancel();
    _updates.close();
  }

  void _onLoungeEvent(LoungeEvent event) {
    switch (event) {
      case NowPlayingEvent e:
        if (e.videoId != null) _videoId = e.videoId;
        if (e.duration > 0) _duration = e.duration;
        _position = e.position;
        _state = e.state;
        _isAd = e.state.isAd;

      case PlaybackStateEvent e:
        if (e.duration > 0) _duration = e.duration;
        _position = e.position;
        _state = e.state;
        _isAd = e.state.isAd;
        if (!_isAd) _adSkippable = false;

      case AdStateEvent e:
        _isAd = true;
        _adSkippable = e.skipEnabled;

      case ScreenDisconnectedEvent():
        _state = PlayerState.stopped;

      default:
        return; // Không ảnh hưởng trạng thái phát.
    }

    _updates.add(PlaybackUpdate(
      videoId: _videoId,
      state: _state,
      position: _position,
      duration: _duration,
      adSkippable: _adSkippable,
      isAd: _isAd,
    ));
  }
}
