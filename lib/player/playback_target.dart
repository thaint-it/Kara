import '../lounge/lounge_events.dart';
import '../models/song.dart';

/// Một lần cập nhật từ bộ phát (TV hoặc trình phát nhúng).
class PlaybackUpdate {
  const PlaybackUpdate({
    this.videoId,
    this.state = PlayerState.stopped,
    this.position = 0,
    this.duration = 0,
    this.adSkippable = false,
    this.isAd = false,
    this.errorCode,
  });

  final String? videoId;
  final PlayerState state;
  final double position;
  final double duration;

  /// Đang có quảng cáo bỏ qua được ⇒ hiện nút "Bỏ quảng cáo".
  final bool adSkippable;
  final bool isAd;

  /// Mã lỗi của IFrame Player API. `101`/`150` = video không cho nhúng.
  final int? errorCode;

  bool get isEmbedBlocked => errorCode == 101 || errorCode == 150;
}

/// Giao diện chung cho hai chế độ phát, để [RoomController] không cần biết
/// đang phát ra TV hay ra điện thoại.
abstract class PlaybackTarget {
  /// Luồng cập nhật trạng thái phát.
  Stream<PlaybackUpdate> get updates;

  /// Bật bộ phát (mở phiên với TV / tạo WebView).
  Future<void> attach();

  /// Tắt bộ phát khi đổi chế độ hoặc đóng app.
  Future<void> detach();

  /// Phát một bài từ đầu.
  Future<void> load(Song song);

  Future<void> play();

  Future<void> pause();

  /// Dừng hẳn, không phát gì (hết hàng chờ).
  Future<void> stop();

  Future<void> seek(double seconds);

  Future<void> setVolume(int volume);

  /// Bỏ quảng cáo nếu bộ phát hỗ trợ.
  Future<void> skipAd() async {}

  /// `true` nếu bộ phát này sẵn sàng nhận lệnh.
  bool get isReady;
}
