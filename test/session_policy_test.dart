import 'package:flutter_test/flutter_test.dart';
import 'package:kara/core/session_policy.dart';

void main() {
  const policy = SessionPolicy();
  final t0 = DateTime(2026, 10, 5, 20, 0, 0);
  const sixHours = Duration(hours: 6);

  group('Tự kết thúc khi không hoạt động', () {
    test('đang hát thì không kết thúc', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(minutes: 30)),
          lastActivityAt: t0.add(const Duration(minutes: 29)),
          idleTimeout: sixHours,
          queueEmpty: false,
        ),
        isNull,
      );
    });

    test('nghỉ giữa buổi 2 tiếng vẫn chưa kết thúc', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(hours: 2)),
          lastActivityAt: t0,
          idleTimeout: sixHours,
          queueEmpty: false,
        ),
        isNull,
      );
    });

    test('quá 6 giờ không ai dùng thì kết thúc', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(hours: 6, minutes: 1)),
          lastActivityAt: t0,
          idleTimeout: sixHours,
        ),
        SessionEndReason.idle,
      );
    });

    test('kết thúc kể cả khi hàng chờ vẫn còn bài', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(days: 7)),
          lastActivityAt: t0,
          idleTimeout: sixHours,
          queueEmpty: false,
        ),
        SessionEndReason.idle,
        reason: 'Hàng chờ của tuần trước là hàng chờ cũ, không phải buổi đang hát',
      );
    });

    test('tắt tính năng thì không bao giờ tự kết thúc', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(days: 30)),
          lastActivityAt: t0,
          idleTimeout: Duration.zero,
        ),
        isNull,
      );
    });

    test('đổi được mốc thời gian', () {
      final at = t0.add(const Duration(hours: 4));
      expect(
        policy.evaluate(
          now: at,
          lastActivityAt: t0,
          idleTimeout: const Duration(hours: 3),
        ),
        SessionEndReason.idle,
      );
      expect(
        policy.evaluate(
          now: at,
          lastActivityAt: t0,
          idleTimeout: const Duration(hours: 12),
        ),
        isNull,
      );
    });
  });

  group('TV mất kết nối', () {
    /// Đặc tả mục 12: TV tắt / đổi WiFi giữa chừng phải **giữ nguyên hàng chờ**.
    test('TV tắt vài phút giữa buổi không kết thúc buổi hát', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(minutes: 5)),
          lastActivityAt: t0,
          idleTimeout: sixHours,
          tvOfflineSince: t0,
          queueEmpty: false,
        ),
        isNull,
      );
    });

    test('TV mất kết nối 3 giờ nhưng còn bài chờ thì vẫn giữ hàng chờ', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(hours: 3)),
          lastActivityAt: t0.add(const Duration(hours: 2, minutes: 55)),
          idleTimeout: sixHours,
          tvOfflineSince: t0,
          queueEmpty: false,
        ),
        isNull,
      );
    });

    test('TV mất kết nối quá 2 giờ và hàng chờ trống thì kết thúc', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(hours: 2, minutes: 1)),
          lastActivityAt: t0.add(const Duration(hours: 2)),
          idleTimeout: sixHours,
          tvOfflineSince: t0,
        ),
        SessionEndReason.tvOffline,
      );
    });

    test('không dùng TV thì không có mốc này', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(hours: 5)),
          lastActivityAt: t0.add(const Duration(hours: 4, minutes: 59)),
          idleTimeout: sixHours,
        ),
        isNull,
      );
    });

    test('mốc không hoạt động được ưu tiên báo trước', () {
      expect(
        policy.evaluate(
          now: t0.add(const Duration(hours: 10)),
          lastActivityAt: t0,
          idleTimeout: sixHours,
          tvOfflineSince: t0,
        ),
        SessionEndReason.idle,
      );
    });
  });
}
