import 'package:flutter_test/flutter_test.dart';
import 'package:kara/player/auto_advance.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 20, 0, 0);

  group('AutoAdvanceGuard', () {
    test('chuyển bài khi thật sự hết bài', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);

      final decision = guard.evaluate(
        now: t0.add(const Duration(minutes: 4)),
        position: 240,
        duration: 240,
      );

      expect(decision, AdvanceDecision.advance);
    });

    test('bỏ qua sự kiện của bài trước đến trễ ngay sau khi gửi bài mới', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);

      final decision = guard.evaluate(
        now: t0.add(const Duration(seconds: 3)),
        position: 200,
        duration: 200,
      );

      expect(decision, AdvanceDecision.tooSoonAfterLoad);
    });

    test('bỏ qua khi vị trí phát còn xa cuối bài', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);

      final decision = guard.evaluate(
        now: t0.add(const Duration(minutes: 1)),
        position: 60,
        duration: 240,
      );

      expect(decision, AdvanceDecision.notAtEnd);
    });

    test('chấp nhận sai lệch 5 giây ở cuối bài', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);

      final decision = guard.evaluate(
        now: t0.add(const Duration(minutes: 4)),
        position: 237,
        duration: 240,
      );

      expect(decision, AdvanceDecision.advance);
    });

    test('chống lặp: hai sự kiện hết bài liền nhau chỉ chuyển một lần', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);
      final at = t0.add(const Duration(minutes: 4));

      expect(
        guard.evaluate(now: at, position: 240, duration: 240),
        AdvanceDecision.advance,
      );
      guard.markAdvanced(at);

      expect(
        guard.evaluate(
          now: at.add(const Duration(seconds: 2)),
          position: 240,
          duration: 240,
        ),
        AdvanceDecision.debounced,
      );
    });

    test('duration chưa biết thì chỉ dựa vào mốc thời gian', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);

      expect(
        guard.evaluate(
          now: t0.add(const Duration(seconds: 2)),
          position: 0,
          duration: 0,
        ),
        AdvanceDecision.tooSoonAfterLoad,
      );
      expect(
        guard.evaluate(
          now: t0.add(const Duration(seconds: 30)),
          position: 0,
          duration: 0,
        ),
        AdvanceDecision.advance,
      );
    });

    test('reset xoá hết mốc thời gian', () {
      final guard = AutoAdvanceGuard()..markLoaded(t0);
      guard.reset();

      expect(
        guard.evaluate(now: t0, position: 0, duration: 0),
        AdvanceDecision.advance,
      );
    });
  });
}
