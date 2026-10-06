import 'package:flutter_test/flutter_test.dart';
import 'package:kara/lounge/browser_channel.dart';

void main() {
  group('BrowserChannelParser', () {
    test('đọc được một khối hoàn chỉnh', () {
      final parser = BrowserChannelParser();
      final batches = parser.push(
        '52\n[[0,["c","SID123","",8]],[1,["S","gsession456"]]]\n',
      );

      expect(batches, hasLength(1));
      expect(batches.first.first[1][0], 'c');
      expect(batches.first.first[1][1], 'SID123');
      expect(batches.first.last[1][0], 'S');
    });

    test('ghép lại khối bị cắt giữa hai đoạn dữ liệu', () {
      final parser = BrowserChannelParser();

      expect(parser.push('40\n[[2,["onStateChange",{"state":"1"'), isEmpty);

      final batches = parser.push(',"currentTime":"12.5"}]]]\n');
      expect(batches, hasLength(1));
      expect(batches.first.first[1][1]['currentTime'], '12.5');
    });

    test('đọc nhiều khối trong cùng một đoạn', () {
      final parser = BrowserChannelParser();
      final batches = parser.push(
        '20\n[[1,["noop"]]]\n21\n[[2,["onVolumeChanged",{"volume":"42"}]]]\n',
      );

      expect(batches, hasLength(2));
      expect(batches[1].first[1][1]['volume'], '42');
    });

    /// Độ dài khối do YouTube gửi đếm theo byte hay ký tự là chuyện không chắc
    /// chắn; tiêu đề tiếng Việt làm hai con số đó lệch nhau. Parser phải không
    /// phụ thuộc vào con số này.
    test('không bị lệch khi nội dung có chữ tiếng Việt có dấu', () {
      final parser = BrowserChannelParser();
      final batches = parser.push(
        '15\n[[3,["nowPlaying",{"videoId":"abc","title":"Hoa nở về đêm"}]]]\n',
      );

      expect(batches, hasLength(1));
      expect(batches.first.first[1][1]['title'], 'Hoa nở về đêm');
    });

    test('dấu ngoặc vuông trong tiêu đề không làm đóng khối sớm', () {
      final parser = BrowserChannelParser();
      final batches = parser.push(
        '99\n[[4,["nowPlaying",{"title":"[KARAOKE] Đắp mộ cuộc tình ]["}]]]\n',
      );

      expect(batches, hasLength(1));
      expect(
        batches.first.first[1][1]['title'],
        '[KARAOKE] Đắp mộ cuộc tình ][',
      );
    });

    test('bỏ qua dòng độ dài khi chưa có dữ liệu JSON', () {
      final parser = BrowserChannelParser();
      expect(parser.push('123\n'), isEmpty);
      expect(parser.push('[[9,["noop"]]]\n'), hasLength(1));
    });
  });
}
