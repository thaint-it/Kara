import 'package:flutter/foundation.dart';

/// Một khách đã vào phòng. `id` do trình duyệt của khách tự sinh và lưu lại,
/// nên khách đóng trình duyệt mở lại vẫn thấy yêu cầu cũ của mình.
@immutable
class Guest {
  const Guest({
    required this.id,
    required this.name,
    this.trusted = false,
    required this.lastSeen,
  });

  final String id;
  final String name;

  /// "Tin tưởng khách này" – yêu cầu của người này tự duyệt.
  final bool trusted;
  final DateTime lastSeen;

  Guest copyWith({String? name, bool? trusted, DateTime? lastSeen}) => Guest(
        id: id,
        name: name ?? this.name,
        trusted: trusted ?? this.trusted,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trusted': trusted,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory Guest.fromJson(Map<String, dynamic> j) => Guest(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Khách',
        trusted: j['trusted'] as bool? ?? false,
        lastSeen:
            DateTime.tryParse(j['lastSeen'] as String? ?? '') ?? DateTime.now(),
      );
}
