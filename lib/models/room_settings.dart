import 'package:flutter/foundation.dart';

/// Chế độ phát (mục 2.5 của đặc tả).
enum PlaybackMode {
  /// Điều khiển app YouTube trên Smart TV qua WiFi.
  tv('tv', 'Phát trên TV'),

  /// Phát ngay trên điện thoại chủ phòng.
  phone('phone', 'Phát trên điện thoại này');

  const PlaybackMode(this.wire, this.label);

  final String wire;
  final String label;

  static PlaybackMode parse(String? v) =>
      PlaybackMode.values.firstWhere((m) => m.wire == v, orElse: () => tv);
}

/// Các tuỳ chọn trong Cài đặt của chủ phòng (mục 3).
@immutable
class RoomSettings {
  const RoomSettings({
    this.mode = PlaybackMode.tv,
    this.autoApprove = false,
    this.guestControl = false,
    this.maxPendingPerGuest = 3,
    this.preferKaraoke = true,
    this.volume = 60,
    this.sessionIdleHours = 6,
  });

  /// Số giờ không hoạt động thì tự kết thúc buổi hát. `0` = không bao giờ.
  final int sessionIdleHours;

  Duration get sessionIdleTimeout => Duration(hours: sessionIdleHours);

  /// Các lựa chọn hiện trong Cài đặt.
  static const idleHourChoices = [3, 6, 12, 0];

  /// Mọi yêu cầu vào thẳng hàng chờ.
  final bool autoApprove;

  /// Khách được bấm Qua bài / Tạm dừng.
  final bool guestControl;

  /// Giới hạn số bài *đang chờ duyệt* của mỗi khách.
  final int maxPendingPerGuest;

  /// Tự thêm chữ "karaoke" vào từ khoá tìm kiếm.
  final bool preferKaraoke;

  final PlaybackMode mode;
  final int volume;

  RoomSettings copyWith({
    PlaybackMode? mode,
    bool? autoApprove,
    bool? guestControl,
    int? maxPendingPerGuest,
    bool? preferKaraoke,
    int? volume,
    int? sessionIdleHours,
  }) =>
      RoomSettings(
        mode: mode ?? this.mode,
        autoApprove: autoApprove ?? this.autoApprove,
        guestControl: guestControl ?? this.guestControl,
        maxPendingPerGuest: maxPendingPerGuest ?? this.maxPendingPerGuest,
        preferKaraoke: preferKaraoke ?? this.preferKaraoke,
        volume: volume ?? this.volume,
        sessionIdleHours: sessionIdleHours ?? this.sessionIdleHours,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.wire,
        'autoApprove': autoApprove,
        'guestControl': guestControl,
        'maxPendingPerGuest': maxPendingPerGuest,
        'preferKaraoke': preferKaraoke,
        'volume': volume,
        'sessionIdleHours': sessionIdleHours,
      };

  factory RoomSettings.fromJson(Map<String, dynamic> j) => RoomSettings(
        mode: PlaybackMode.parse(j['mode'] as String?),
        autoApprove: j['autoApprove'] as bool? ?? false,
        guestControl: j['guestControl'] as bool? ?? false,
        maxPendingPerGuest: (j['maxPendingPerGuest'] as num?)?.toInt() ?? 3,
        preferKaraoke: j['preferKaraoke'] as bool? ?? true,
        volume: (j['volume'] as num?)?.toInt() ?? 60,
        sessionIdleHours: (j['sessionIdleHours'] as num?)?.toInt() ?? 6,
      );
}
