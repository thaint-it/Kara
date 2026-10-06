import 'package:flutter/foundation.dart';

/// Một video YouTube có thể hát.
@immutable
class Song {
  const Song({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.durationSec,
    required this.thumbUrl,
    this.viewCount,
    this.publishedText,
    this.embeddable,
  });

  final String videoId;
  final String title;
  final String channel;
  final int durationSec;
  final String thumbUrl;
  final int? viewCount;
  final String? publishedText;

  /// `false` nếu biết chắc video không cho nhúng (chế độ phát trên điện thoại
  /// sẽ không phát được). `null` = chưa rõ.
  final bool? embeddable;

  String get url => 'https://www.youtube.com/watch?v=$videoId';

  /// "3:45" hoặc "1:02:30".
  String get durationText => formatDuration(durationSec);

  /// "1,2 Tr lượt xem" – gọn theo kiểu YouTube tiếng Việt.
  String? get viewCountText {
    final v = viewCount;
    if (v == null || v <= 0) return null;
    if (v >= 1000000000) return '${_oneDecimal(v / 1000000000)} T lượt xem';
    if (v >= 1000000) return '${_oneDecimal(v / 1000000)} Tr lượt xem';
    if (v >= 1000) return '${_oneDecimal(v / 1000)} N lượt xem';
    return '$v lượt xem';
  }

  Song copyWith({bool? embeddable}) => Song(
        videoId: videoId,
        title: title,
        channel: channel,
        durationSec: durationSec,
        thumbUrl: thumbUrl,
        viewCount: viewCount,
        publishedText: publishedText,
        embeddable: embeddable ?? this.embeddable,
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channel': channel,
        'durationSec': durationSec,
        'thumbUrl': thumbUrl,
        if (viewCount != null) 'viewCount': viewCount,
        if (publishedText != null) 'publishedText': publishedText,
        if (embeddable != null) 'embeddable': embeddable,
        'durationText': durationText,
        if (viewCountText != null) 'viewCountText': viewCountText,
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        videoId: j['videoId'] as String,
        title: j['title'] as String? ?? '',
        channel: j['channel'] as String? ?? '',
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        thumbUrl: j['thumbUrl'] as String? ?? thumbnailFor(j['videoId'] as String),
        viewCount: (j['viewCount'] as num?)?.toInt(),
        publishedText: j['publishedText'] as String?,
        embeddable: j['embeddable'] as bool?,
      );

  static String thumbnailFor(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

  @override
  bool operator ==(Object other) =>
      other is Song && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}

String formatDuration(int totalSeconds) {
  if (totalSeconds <= 0) return '--:--';
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  return h > 0
      ? '$h:$mm:${s.toString().padLeft(2, '0')}'
      : '$mm:${s.toString().padLeft(2, '0')}';
}

String _oneDecimal(double v) {
  final s = v.toStringAsFixed(v >= 10 ? 0 : 1);
  return s.replaceAll('.', ',');
}
