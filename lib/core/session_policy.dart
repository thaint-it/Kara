/// Vì sao một buổi hát kết thúc.
enum SessionEndReason {
  /// Chủ phòng tự bấm "Kết thúc buổi hát".
  manual(
    'Đã kết thúc buổi hát',
    'Hàng chờ và danh sách khách đã được xoá. Mã phòng mới đã sinh, khách cần '
        'quét lại mã QR.',
  ),

  /// Không có bài nào được phát và không ai gửi yêu cầu trong nhiều giờ.
  idle(
    'Buổi hát trước đã kết thúc',
    'Không có ai dùng trong nhiều giờ nên hàng chờ cũ đã được xoá.',
  ),

  /// TV mất kết nối quá lâu trong khi không còn bài nào chờ.
  tvOffline(
    'Buổi hát trước đã kết thúc',
    'TV mất kết nối quá lâu và hàng chờ đã trống nên buổi hát được đóng lại.',
  );

  const SessionEndReason(this.title, this.detail);

  final String title;
  final String detail;
}

/// Quyết định khi nào một buổi hát karaoke được coi là đã tàn.
///
/// Tách riêng khỏi [RoomController] và không phụ thuộc Flutter để kiểm thử
/// được bằng `DateTime` giả — đây là logic duy nhất trong app có quyền **xoá**
/// hàng chờ của người dùng, nên cần chắc chắn.
///
/// Cố ý **không** kết thúc buổi hát ngay khi TV mất kết nối: đặc tả mục 12 yêu
/// cầu giữ nguyên hàng chờ khi TV tắt hoặc đổi WiFi giữa chừng, và trong thực
/// tế thì TV tắt vài phút giữa buổi là chuyện bình thường. TV chỉ góp phần kết
/// thúc buổi hát khi nó mất kết nối rất lâu *và* không còn bài nào chờ.
class SessionPolicy {
  const SessionPolicy({this.tvOfflineTimeout = const Duration(hours: 2)});

  /// TV phải mất kết nối liên tục lâu hơn khoảng này mới tính.
  final Duration tvOfflineTimeout;

  /// Trả về lý do kết thúc, hoặc `null` nếu buổi hát vẫn đang diễn ra.
  ///
  /// [idleTimeout] bằng [Duration.zero] nghĩa là chủ phòng đã tắt tính năng tự
  /// kết thúc.
  ///
  /// [tvOfflineSince] chỉ nên khác `null` khi đang ở chế độ phát ra TV và TV đó
  /// đã từng ghép nối — không có TV thì không có mốc này.
  SessionEndReason? evaluate({
    required DateTime now,
    required DateTime lastActivityAt,
    required Duration idleTimeout,
    DateTime? tvOfflineSince,
    bool queueEmpty = true,
  }) {
    if (idleTimeout > Duration.zero &&
        now.difference(lastActivityAt) >= idleTimeout) {
      return SessionEndReason.idle;
    }

    if (queueEmpty &&
        tvOfflineSince != null &&
        now.difference(tvOfflineSince) >= tvOfflineTimeout) {
      return SessionEndReason.tvOffline;
    }

    return null;
  }
}
