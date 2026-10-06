/// Trạng thái bộ phát của app YouTube trên TV (mục 7.3 của đặc tả).
enum PlayerState {
  stopped(-1),
  ended(0),
  playing(1),
  paused(2),
  buffering(3),
  cued(5),
  advertisement(1081),
  adSkipped(1082);

  const PlayerState(this.code);

  final int code;

  static PlayerState parse(Object? raw) {
    final code = switch (raw) {
      int v => v,
      String v => int.tryParse(v) ?? -1,
      _ => -1,
    };
    for (final s in PlayerState.values) {
      if (s.code == code) return s;
    }
    return PlayerState.stopped;
  }

  bool get isAd => this == advertisement || this == adSkipped;
}

/// Sự kiện nhận được từ TV. Chỉ mô hình hoá những sự kiện đặc tả cần dùng,
/// phần còn lại giữ nguyên dạng [LoungeRawEvent] để dễ gỡ lỗi.
sealed class LoungeEvent {
  const LoungeEvent();
}

/// `nowPlaying` – TV cho biết đang phát video nào.
class NowPlayingEvent extends LoungeEvent {
  const NowPlayingEvent({
    this.videoId,
    this.position = 0,
    this.duration = 0,
    this.state = PlayerState.stopped,
  });

  final String? videoId;
  final double position;
  final double duration;
  final PlayerState state;

  factory NowPlayingEvent.fromJson(Map<String, dynamic> d) => NowPlayingEvent(
        videoId: (d['videoId'] as String?)?.trim().isEmpty ?? true
            ? null
            : d['videoId'] as String,
        position: _num(d['currentTime']),
        duration: _num(d['duration']),
        state: d.containsKey('state')
            ? PlayerState.parse(d['state'])
            : PlayerState.stopped,
      );
}

/// `onStateChange` – tiến độ và trạng thái phát.
class PlaybackStateEvent extends LoungeEvent {
  const PlaybackStateEvent({
    required this.position,
    required this.duration,
    required this.state,
  });

  final double position;
  final double duration;
  final PlayerState state;

  factory PlaybackStateEvent.fromJson(Map<String, dynamic> d) =>
      PlaybackStateEvent(
        position: _num(d['currentTime']),
        duration: _num(d['duration']),
        state: PlayerState.parse(d['state']),
      );
}

/// `onVolumeChanged`
class VolumeChangedEvent extends LoungeEvent {
  const VolumeChangedEvent({required this.volume, required this.muted});

  final int volume;
  final bool muted;

  factory VolumeChangedEvent.fromJson(Map<String, dynamic> d) =>
      VolumeChangedEvent(
        volume: _num(d['volume']).round(),
        muted: d['muted'] == 'true' || d['muted'] == true,
      );
}

/// `onAdStateChange` / `adPlaying` – để hiện nút "Bỏ quảng cáo".
class AdStateEvent extends LoungeEvent {
  const AdStateEvent({required this.skipEnabled, required this.state});

  final bool skipEnabled;
  final PlayerState state;

  factory AdStateEvent.fromJson(Map<String, dynamic> d) => AdStateEvent(
        skipEnabled: d['isSkipEnabled'] == 'true' || d['isSkipEnabled'] == true,
        state: PlayerState.parse(d['adState']),
      );
}

/// `onAutoplayModeChanged` – xác nhận đã tắt tự phát video gợi ý.
class AutoplayModeEvent extends LoungeEvent {
  const AutoplayModeEvent({required this.enabled, required this.supported});

  final bool enabled;
  final bool supported;

  factory AutoplayModeEvent.fromJson(Map<String, dynamic> d) =>
      AutoplayModeEvent(
        enabled: d['autoplayMode'] == 'ENABLED',
        supported: d['autoplayMode'] != 'UNSUPPORTED',
      );
}

/// `loungeStatus` – chứa tên và thông tin thiết bị của TV.
class LoungeStatusEvent extends LoungeEvent {
  const LoungeStatusEvent({this.screenName, this.deviceName});

  final String? screenName;
  final String? deviceName;
}

/// `loungeScreenDisconnected` – TV rời phiên.
class ScreenDisconnectedEvent extends LoungeEvent {
  const ScreenDisconnectedEvent({this.reason});

  final String? reason;
}

/// Sự kiện chưa xử lý, giữ lại để ghi log.
class LoungeRawEvent extends LoungeEvent {
  const LoungeRawEvent(this.type, this.args);

  final String type;
  final List<dynamic> args;
}

double _num(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };
