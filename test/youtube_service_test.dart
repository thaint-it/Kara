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

  group('parseNextResponse – bài đề xuất từ youtubei/v1/next', () {
    Map<String, dynamic> lockup({
      required String id,
      required String title,
      String type = 'LOCKUP_CONTENT_TYPE_VIDEO',
      String? duration = '4:11',
    }) =>
        {
          'lockupViewModel': {
            'contentId': id,
            'contentType': type,
            'contentImage': {
              'thumbnailViewModel': {
                'overlays': [
                  {
                    'thumbnailBottomOverlayViewModel': {
                      'badges': [
                        if (duration != null)
                          {
                            'thumbnailBadgeViewModel': {'text': duration},
                          },
                      ],
                    },
                  },
                ],
              },
            },
            'metadata': {
              'lockupMetadataViewModel': {
                'title': {'content': title},
                'metadata': {
                  'contentMetadataViewModel': {
                    'metadataRows': [
                      {
                        'metadataParts': [
                          {
                            'text': {'content': 'Thiện Trung Guitar'},
                          },
                        ],
                      },
                      {
                        'metadataParts': [
                          {
                            'text': {'content': '2,2 Tr'},
                            'accessibilityLabel': '2,2 triệu lượt xem',
                          },
                          {
                            'text': {'content': '1 năm trước'},
                          },
                        ],
                      },
                    ],
                  },
                },
              },
            },
          },
        };

    test('đọc tên bài, kênh, lượt xem, ngày đăng, thời lượng', () {
      final json = {
        'contents': {
          'results': [
            lockup(id: 'abc123', title: 'Karaoke Trời giấu trời mang đi'),
          ],
        },
      };
      final songs = YoutubeService.parseNextResponse(json);
      expect(songs, hasLength(1));
      final s = songs.single;
      expect(s.videoId, 'abc123');
      expect(s.title, 'Karaoke Trời giấu trời mang đi');
      expect(s.channel, 'Thiện Trung Guitar');
      expect(s.viewCount, 2200000);
      expect(s.publishedText, '1 năm trước');
      expect(s.durationSec, 251);
    });

    test('bỏ danh sách phát / mix, chỉ giữ video', () {
      final json = [
        lockup(id: 'v1', title: 'Bài 1'),
        lockup(id: 'p1', title: 'Mix', type: 'LOCKUP_CONTENT_TYPE_PLAYLIST'),
      ];
      expect(
        YoutubeService.parseNextResponse(json).map((s) => s.videoId),
        ['v1'],
      );
    });

    test('phản hồi lạ thì trả về rỗng, không ném lỗi', () {
      expect(YoutubeService.parseNextResponse(null), isEmpty);
      expect(YoutubeService.parseNextResponse({'error': 1}), isEmpty);
    });
  });

  group('parseCompactCount – lượt xem rút gọn', () {
    test('N / Tr / T kiểu YouTube tiếng Việt', () {
      expect(YoutubeService.parseCompactCount('24 N'), 24000);
      expect(YoutubeService.parseCompactCount('2,2 Tr'), 2200000);
      expect(YoutubeService.parseCompactCount('1,1 T'), 1100000000);
    });

    test('số đầy đủ có dấu chấm nghìn', () {
      expect(YoutubeService.parseCompactCount('950'), 950);
      expect(YoutubeService.parseCompactCount('12.345'), 12345);
      expect(YoutubeService.parseCompactCount(null), isNull);
    });
  });

  group('localizeUploadDate – ngày đăng tiếng Việt', () {
    test('dạng viết tắt và viết đầy đủ', () {
      expect(YoutubeService.localizeUploadDate('9y ago'), '9 năm trước');
      expect(YoutubeService.localizeUploadDate('3 months ago'), '3 tháng trước');
      expect(YoutubeService.localizeUploadDate('2mo ago'), '2 tháng trước');
      expect(YoutubeService.localizeUploadDate('1 week ago'), '1 tuần trước');
      expect(YoutubeService.localizeUploadDate('5 days ago'), '5 ngày trước');
      expect(YoutubeService.localizeUploadDate('4h ago'), '4 giờ trước');
      expect(YoutubeService.localizeUploadDate('10 minutes ago'), '10 phút trước');
    });

    test('video từng phát trực tiếp', () {
      expect(
        YoutubeService.localizeUploadDate('Streamed 2 years ago'),
        'Đã phát trực tiếp 2 năm trước',
      );
    });

    test('không nhận ra thì giữ nguyên, rỗng thì bỏ', () {
      expect(YoutubeService.localizeUploadDate('12/3/2020'), '12/3/2020');
      expect(YoutubeService.localizeUploadDate(''), isNull);
      expect(YoutubeService.localizeUploadDate(null), isNull);
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
