import 'package:flutter_test/flutter_test.dart';
import 'package:kara/server/rate_limiter.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 20, 0, 0);

  group('RateLimiter – 10 yêu cầu / phút / khách', () {
    test('cho qua 10 lần đầu rồi chặn', () {
      final limiter = RateLimiter();

      for (var i = 0; i < 10; i++) {
        expect(limiter.allow('khach-1', now: t0), isTrue, reason: 'lần $i');
      }
      expect(limiter.allow('khach-1', now: t0), isFalse);
    });

    test('mỗi khách có hạn mức riêng', () {
      final limiter = RateLimiter();

      for (var i = 0; i < 10; i++) {
        limiter.allow('khach-1', now: t0);
      }
      expect(limiter.allow('khach-2', now: t0), isTrue);
    });

    test('cho qua lại sau khi cửa sổ thời gian trôi qua', () {
      final limiter = RateLimiter();

      for (var i = 0; i < 10; i++) {
        limiter.allow('khach-1', now: t0);
      }
      expect(
        limiter.allow('khach-1', now: t0.add(const Duration(seconds: 61))),
        isTrue,
      );
    });

    test('báo đúng số giây phải đợi', () {
      final limiter = RateLimiter();
      for (var i = 0; i < 10; i++) {
        limiter.allow('khach-1', now: t0);
      }

      final wait = limiter.retryAfterSeconds(
        'khach-1',
        now: t0.add(const Duration(seconds: 20)),
      );
      expect(wait, inInclusiveRange(40, 41));
    });
  });
}
