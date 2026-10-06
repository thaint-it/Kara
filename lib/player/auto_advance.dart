/// Vì sao một sự kiện "hết bài" bị bỏ qua (hoặc được chấp nhận).
enum AdvanceDecision {
  /// Thật sự hết bài – chuyển sang bài kế tiếp.
  advance('chuyển bài'),

  /// Bài vừa được gửi, sự kiện này là của bài trước đến trễ.
  tooSoonAfterLoad('bài vừa gửi < 8s'),

  /// `currentTime` còn xa `duration` ⇒ không phải hết bài thật.
  notAtEnd('chưa tới cuối bài'),

  /// Vừa chuyển bài xong, chống lặp.
  debounced('vừa chuyển bài < 5s');

  const AdvanceDecision(this.reason);

  final String reason;

  bool get shouldAdvance => this == AdvanceDecision.advance;
}

/// Bộ lọc sự kiện "hết bài" (mục 7.4 của đặc tả).
///
/// App YouTube trên TV và YouTube IFrame Player API đều bắn `state == 0` khá
/// bừa: sự kiện của bài cũ đến trễ sau khi đã gửi bài mới, hoặc bắn nhiều lần
/// liên tiếp. Nếu tin ngay thì hàng chờ bị nhảy mất mấy bài một lúc.
///
/// Lớp này không phụ thuộc Flutter để kiểm thử được bằng `DateTime` giả.
class AutoAdvanceGuard {
  AutoAdvanceGuard({
    this.loadGrace = const Duration(seconds: 8),
    this.advanceDebounce = const Duration(seconds: 5),
    this.endTolerance = 5,
  });

  /// Bỏ qua sự kiện hết bài đến trong khoảng này sau khi gửi bài mới.
  final Duration loadGrace;

  /// Hai lần chuyển bài phải cách nhau tối thiểu khoảng này.
  final Duration advanceDebounce;

  /// `position` phải nằm trong `duration - endTolerance` giây mới coi là hết.
  final double endTolerance;

  DateTime? _loadedAt;
  DateTime? _advancedAt;

  /// Gọi ngay khi gửi một bài mới tới bộ phát.
  void markLoaded(DateTime now) {
    _loadedAt = now;
  }

  /// Gọi sau khi đã thực sự chuyển bài (kể cả khi do người dùng bấm Qua bài).
  void markAdvanced(DateTime now) {
    _advancedAt = now;
  }

  void reset() {
    _loadedAt = null;
    _advancedAt = null;
  }

  /// Quyết định có nên chuyển bài khi nhận `state == 0`.
  ///
  /// [duration] bằng 0 nghĩa là bộ phát chưa báo thời lượng – lúc đó bỏ qua
  /// điều kiện "chưa tới cuối bài" và chỉ dựa vào hai mốc thời gian.
  AdvanceDecision evaluate({
    required DateTime now,
    required double position,
    required double duration,
  }) {
    final loadedAt = _loadedAt;
    if (loadedAt != null && now.difference(loadedAt) < loadGrace) {
      return AdvanceDecision.tooSoonAfterLoad;
    }

    if (duration > 0 && position < duration - endTolerance) {
      return AdvanceDecision.notAtEnd;
    }

    final advancedAt = _advancedAt;
    if (advancedAt != null && now.difference(advancedAt) < advanceDebounce) {
      return AdvanceDecision.debounced;
    }

    return AdvanceDecision.advance;
  }
}
