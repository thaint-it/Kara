import 'package:flutter/foundation.dart';

import 'song.dart';

/// Trạng thái một yêu cầu bài hát trong vòng đời của nó.
enum QueueStatus {
  pending('pending', 'Chờ duyệt'),
  queued('queued', 'Trong hàng chờ'),
  playing('playing', 'Đang hát'),
  played('played', 'Đã hát'),
  rejected('rejected', 'Bị từ chối'),
  skipped('skipped', 'Đã bỏ qua'),
  cancelled('cancelled', 'Đã huỷ');

  const QueueStatus(this.wire, this.label);

  final String wire;
  final String label;

  static QueueStatus parse(String? v) => QueueStatus.values.firstWhere(
        (s) => s.wire == v,
        orElse: () => QueueStatus.pending,
      );
}

/// Người yêu cầu bài – chỉ cần đủ để hiển thị.
@immutable
class Requester {
  const Requester({required this.guestId, required this.name});

  /// Chủ phòng tự thêm bài thì dùng mã này.
  static const hostId = 'host';
  static const host = Requester(guestId: hostId, name: 'Chủ phòng');

  final String guestId;
  final String name;

  bool get isHost => guestId == hostId;

  Map<String, dynamic> toJson() => {'guestId': guestId, 'name': name};

  factory Requester.fromJson(Map<String, dynamic> j) => Requester(
        guestId: j['guestId'] as String? ?? hostId,
        name: j['name'] as String? ?? 'Khách',
      );
}

/// Một mục trong hàng chờ / danh sách yêu cầu / lịch sử.
@immutable
class QueueItem {
  const QueueItem({
    required this.uid,
    required this.song,
    required this.requestedBy,
    required this.status,
    required this.createdAt,
    this.approvedAt,
    this.playedAt,
    this.note,
  });

  final String uid;
  final Song song;
  final Requester requestedBy;
  final QueueStatus status;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? playedAt;

  /// Ghi chú hiện cho khách, ví dụ "Bài này không phát được ngoài YouTube".
  final String? note;

  QueueItem copyWith({
    QueueStatus? status,
    DateTime? approvedAt,
    DateTime? playedAt,
    String? note,
    Song? song,
  }) =>
      QueueItem(
        uid: uid,
        song: song ?? this.song,
        requestedBy: requestedBy,
        status: status ?? this.status,
        createdAt: createdAt,
        approvedAt: approvedAt ?? this.approvedAt,
        playedAt: playedAt ?? this.playedAt,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'song': song.toJson(),
        'requestedBy': requestedBy.toJson(),
        'status': status.wire,
        'createdAt': createdAt.toIso8601String(),
        if (approvedAt != null) 'approvedAt': approvedAt!.toIso8601String(),
        if (playedAt != null) 'playedAt': playedAt!.toIso8601String(),
        if (note != null) 'note': note,
      };

  factory QueueItem.fromJson(Map<String, dynamic> j) => QueueItem(
        uid: j['uid'] as String,
        song: Song.fromJson(j['song'] as Map<String, dynamic>),
        requestedBy:
            Requester.fromJson(j['requestedBy'] as Map<String, dynamic>? ?? {}),
        status: QueueStatus.parse(j['status'] as String?),
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        approvedAt: DateTime.tryParse(j['approvedAt'] as String? ?? ''),
        playedAt: DateTime.tryParse(j['playedAt'] as String? ?? ''),
        note: j['note'] as String?,
      );
}
