import 'package:flutter_test/flutter_test.dart';
import 'package:kara/services/youtube_service.dart';

void main() {
  group('buildQuery – công tắc "Ưu tiên bản karaoke"', () {
    test('thêm chữ karaoke khi người dùng chưa gõ', () {
      expect(
        YoutubeService.buildQuery('hoa nở về đêm', preferKaraoke: true),
        'hoa nở về đêm karaoke',
      );
    });

    test('không thêm nếu đã có karaoke / beat / kara', () {
      for (final q in [
        'hoa nở về đêm karaoke',
        'Đắp mộ cuộc tình BEAT',
        'kara duyên phận',
      ]) {
        expect(YoutubeService.buildQuery(q, preferKaraoke: true), q);
      }
    });

    test('tắt công tắc thì tìm y hệt YouTube', () {
      expect(
        YoutubeService.buildQuery('duyên phận', preferKaraoke: false),
        'duyên phận',
      );
    });

    test('từ khoá rỗng thì giữ nguyên rỗng', () {
      expect(YoutubeService.buildQuery('   ', preferKaraoke: true), '');
    });
  });

  group('extractVideoId – dán link YouTube', () {
    test('nhận các dạng link phổ biến', () {
      const expected = 'dQw4w9WgXcQ';
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=30s',
        '  https://www.youtube.com/watch?v=dQw4w9WgXcQ  ',
      ]) {
        expect(YoutubeService.extractVideoId(url), expected, reason: url);
      }
    });

    test('nhận ID dán trực tiếp', () {
      expect(YoutubeService.extractVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });

    test('từ khoá thường không bị nhận là link', () {
      expect(YoutubeService.extractVideoId('hoa nở về đêm karaoke'), isNull);
      expect(YoutubeService.extractVideoId('https://example.com/abc'), isNull);
    });
  });

  group('parseDurationText', () {
    test('đọc được mm:ss và h:mm:ss', () {
      expect(YoutubeService.parseDurationText('3:45'), 225);
      expect(YoutubeService.parseDurationText('1:02:30'), 3750);
      expect(YoutubeService.parseDurationText('0:59'), 59);
    });

    test('trả về 0 với dữ liệu không hợp lệ', () {
      expect(YoutubeService.parseDurationText(null), 0);
      expect(YoutubeService.parseDurationText(''), 0);
      expect(YoutubeService.parseDurationText('LIVE'), 0);
    });
  });

  group('isSingable – lọc livestream và Shorts', () {
    test('bỏ livestream', () {
      expect(
        YoutubeService.isSingable(durationSec: 300, isLive: true),
        isFalse,
      );
    });

    test('bỏ video ngắn dưới 60 giây (Shorts)', () {
      expect(YoutubeService.isSingable(durationSec: 42, isLive: false), isFalse);
    });

    test('giữ video có thời lượng bình thường', () {
      expect(YoutubeService.isSingable(durationSec: 285, isLive: false), isTrue);
    });
  });

  group('parseSuggestResponse', () {
    test('bóc được JSONP của API gợi ý', () {
      const body = 'window.google.ac.h(["hoa n",'
          '[["hoa nở về đêm",0],["hoa nở về đêm karaoke",0]],{}])';

      expect(YoutubeService.parseSuggestResponse(body), [
        'hoa nở về đêm',
        'hoa nở về đêm karaoke',
      ]);
    });

    test('trả về danh sách rỗng khi phản hồi lạ', () {
      expect(YoutubeService.parseSuggestResponse('không phải json'), isEmpty);
      expect(YoutubeService.parseSuggestResponse(''), isEmpty);
    });
  });
}
