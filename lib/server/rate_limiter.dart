/// Giới hạn tần suất theo khoá (ở đây là `guestId`): tối đa [limit] lần trong
/// [window] (mục "Bảo mật cơ bản" – 10 yêu cầu / phút / khách).
class RateLimiter {
  RateLimiter({this.limit = 10, this.window = const Duration(minutes: 1)});

  final int limit;
  final Duration window;

  final _hits = <String, List<DateTime>>{};

  /// `true` nếu lần gọi này được phép (và đã được tính vào hạn mức).
  bool allow(String key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final cutoff = at.subtract(window);
    final hits = _hits.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere((t) => t.isBefore(cutoff));

    if (hits.length >= limit) return false;
    hits.add(at);
    return true;
  }

  /// Số giây phải đợi trước khi được gọi lại.
  int retryAfterSeconds(String key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final hits = _hits[key];
    if (hits == null || hits.isEmpty) return 0;
    final oldest = hits.first;
    final remaining = window - at.difference(oldest);
    return remaining.isNegative ? 0 : remaining.inSeconds + 1;
  }

  void clear() => _hits.clear();
}
