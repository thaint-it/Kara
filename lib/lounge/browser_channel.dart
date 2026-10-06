import 'dart:convert';

/// Bộ phân tích luồng dữ liệu kiểu "BrowserChannel" mà `/bc/bind` trả về.
///
/// Dữ liệu đến dạng:
/// ```
/// 123
/// [[0,["c","<SID>",...]],[1,["S","<gsessionid>"]]]
/// 57
/// [[2,["onStateChange",{"currentTime":"0","state":"1"}]]]
/// ```
/// Dòng số đầu mỗi khối là độ dài khối. Độ dài này đếm theo ký tự hay byte là
/// chuyện không chắc chắn giữa các phiên bản YouTube (tiêu đề tiếng Việt có
/// dấu làm lệch số đếm), nên ở đây bỏ qua con số đó và quét trực tiếp mảng
/// JSON cân ngoặc — cách này không bao giờ lệch.
class BrowserChannelParser {
  String _pending = '';

  /// Nạp thêm một đoạn text, trả về các khối sự kiện đã hoàn chỉnh.
  ///
  /// Mỗi khối là một `List` dạng `[[eventId, [eventType, ...args]], ...]`.
  List<List<dynamic>> push(String text) {
    _pending += text;
    final batches = <List<dynamic>>[];

    while (true) {
      final start = _pending.indexOf('[');
      if (start < 0) {
        // Chỉ còn dòng độ dài, chưa tới phần JSON.
        _pending = '';
        break;
      }
      final end = _findArrayEnd(_pending, start);
      if (end == null) {
        // Khối chưa về hết, giữ lại chờ đoạn sau.
        _pending = _pending.substring(start);
        break;
      }
      final raw = _pending.substring(start, end + 1);
      _pending = _pending.substring(end + 1);
      final decoded = jsonDecode(raw);
      if (decoded is List) batches.add(decoded);
    }

    return batches;
  }

  void reset() => _pending = '';

  /// Tìm vị trí dấu `]` đóng mảng bắt đầu tại [start], bỏ qua ngoặc nằm trong
  /// chuỗi JSON. Trả về `null` nếu mảng chưa đóng.
  static int? _findArrayEnd(String s, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == 0x5C) {
          escaped = true; // \
        } else if (c == 0x22) {
          inString = false; // "
        }
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x5B) {
        depth++; // [
      } else if (c == 0x5D) {
        depth--; // ]
        if (depth == 0) return i;
      }
    }
    return null;
  }
}
