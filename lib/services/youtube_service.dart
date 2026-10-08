import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../models/song.dart';

/// Tìm kiếm YouTube cho cả app chủ phòng và trang khách (mục 6).
///
/// Khách không gọi YouTube trực tiếp được (vướng CORS) nên mọi tìm kiếm đều
/// đi qua lớp này.
class YoutubeService {
  YoutubeService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final _yt = yt.YoutubeExplode();
  final http.Client _http;

  /// Cache kết quả tìm kiếm 10 phút để đỡ gọi lặp.
  static const _cacheTtl = Duration(minutes: 10);
  static const _suggestTtl = Duration(minutes: 30);

  /// Bài hát ngắn hơn mốc này gần như chắc chắn là Shorts ⇒ lọc bỏ.
  static const _minDurationSec = 60;

  final _sessions = <String, _SearchSession>{};
  final _suggestCache = <String, _Cached<List<String>>>{};

  /// Thêm chữ "karaoke" vào từ khoá nếu người dùng chưa gõ `karaoke`/`beat`.
  ///
  /// Tách riêng ra để kiểm thử được.
  static String buildQuery(String raw, {required bool preferKaraoke}) {
    final q = raw.trim();
    if (!preferKaraoke || q.isEmpty) return q;
    final lower = q.toLowerCase();
    if (lower.contains('karaoke') ||
        lower.contains('beat') ||
        lower.contains('kara')) {
      return q;
    }
    return '$q karaoke';
  }

  /// Lấy videoId nếu [text] là một link / ID YouTube.
  static String? extractVideoId(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    if (!t.contains('/') && !t.contains('.') && !t.contains(' ')) {
      // Có thể người dùng dán thẳng ID.
      return yt.VideoId.parseVideoId(t);
    }
    if (!t.contains('youtu')) return null;
    return yt.VideoId.parseVideoId(t);
  }

  // ------------------------------------------------------------- gợi ý

  /// Gợi ý khi gõ, lấy từ API gợi ý của YouTube.
  Future<List<String>> suggest(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final cached = _suggestCache[q];
    if (cached != null && !cached.isExpired(_suggestTtl)) return cached.value;

    // `oe=utf-8`: thiếu nó Google trả ISO-8859-1 và tiếng Việt có dấu giải mã
    // UTF-8 sẽ lỗi.
    final uri = Uri.parse(
      'https://suggestqueries.google.com/complete/search'
      '?client=youtube&ds=yt&hl=vi&oe=utf-8&q=${Uri.encodeQueryComponent(q)}',
    );

    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final items = _parseSuggestResponse(utf8.decode(res.bodyBytes));
      _suggestCache[q] = _Cached(items);
      return items;
    } catch (e) {
      debugPrint('Gợi ý từ khoá thất bại: $e');
      return const [];
    }
  }

  /// Phản hồi là JSONP dạng `window.google.ac.h([ "q", [["gợi ý",0],...] ])`.
  @visibleForTesting
  static List<String> parseSuggestResponse(String body) =>
      _parseSuggestResponse(body);

  static List<String> _parseSuggestResponse(String body) {
    final start = body.indexOf('(');
    final end = body.lastIndexOf(')');
    final json = (start >= 0 && end > start)
        ? body.substring(start + 1, end)
        : body;

    try {
      final decoded = jsonDecode(json);
      if (decoded is! List || decoded.length < 2) return const [];
      final list = decoded[1];
      if (list is! List) return const [];
      return list
          .map((e) => e is List && e.isNotEmpty ? '${e.first}' : '$e')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------- tìm kiếm

  /// Trả về trang kết quả thứ [page] (bắt đầu từ 0) cho [query].
  ///
  /// Nếu [query] là link YouTube thì trả về đúng video đó.
  Future<List<Song>> search(
    String query, {
    int page = 0,
    bool preferKaraoke = true,
  }) async {
    final raw = query.trim();
    if (raw.isEmpty) return const [];

    final videoId = extractVideoId(raw);
    if (videoId != null) {
      if (page > 0) return const [];
      final song = await videoById(videoId);
      return song == null ? const [] : [song];
    }

    final effective = buildQuery(raw, preferKaraoke: preferKaraoke);
    final session = _sessionFor(effective);
    return session.page(page);
  }

  _SearchSession _sessionFor(String query) {
    final existing = _sessions[query];
    if (existing != null && !existing.isExpired(_cacheTtl)) return existing;

    // Dọn các phiên đã hết hạn để không phình bộ nhớ.
    _sessions.removeWhere((_, s) => s.isExpired(_cacheTtl));

    final session = _SearchSession(query, _yt);
    _sessions[query] = session;
    return session;
  }

  /// Lấy thông tin một video theo ID (dùng khi khách dán link).
  Future<Song?> videoById(String videoId) async {
    try {
      final v = await _yt.videos.get(videoId);
      return Song(
        videoId: v.id.value,
        title: v.title,
        channel: v.author,
        durationSec: v.duration?.inSeconds ?? 0,
        thumbUrl: v.thumbnails.mediumResUrl,
        viewCount: v.engagement.viewCount,
        publishedText: v.publishDate == null
            ? null
            : '${v.publishDate!.day}/${v.publishDate!.month}/${v.publishDate!.year}',
      );
    } catch (e) {
      debugPrint('Không lấy được video $videoId: $e');
      return null;
    }
  }

  // ------------------------------------------------------------- đề xuất

  /// API nội bộ mà trang xem video của YouTube dùng để lấy cột "Tiếp theo".
  /// `getRelatedVideos` của youtube_explode 3.0.0 không đọc được định dạng
  /// `lockupViewModel` mới nên phải tự gọi.
  static const _nextUrl =
      'https://www.youtube.com/youtubei/v1/next?prettyPrint=false';
  static const _webClientVersion = '2.20250101.00.00';
  static const _relatedTtl = Duration(minutes: 30);

  /// Đề xuất dài hơn mốc này là tuyển tập / mix hàng giờ, không hát được.
  static const _maxRecommendSec = 12 * 60;

  /// Phòng chưa hát bài nào, hoặc YouTube đổi API đề xuất: dùng tìm kiếm.
  static const fallbackRecommendQuery = 'karaoke nhạc trẻ hay nhất';

  static final _karaokeTitle = RegExp(
    r'karaoke|kara\b|beat|tone (nam|nữ)|instrumental',
    caseSensitive: false,
  );

  final _relatedCache = <String, _Cached<List<Song>>>{};

  /// Video YouTube đề xuất bên cạnh [videoId].
  Future<List<Song>> related(String videoId) async {
    final cached = _relatedCache[videoId];
    if (cached != null && !cached.isExpired(_relatedTtl)) return cached.value;

    try {
      final res = await _http
          .post(
            Uri.parse(_nextUrl),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': _webClientVersion,
                  'hl': 'vi',
                  'gl': 'VN',
                },
              },
              'videoId': videoId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return const [];
      final songs = parseNextResponse(jsonDecode(utf8.decode(res.bodyBytes)));
      _relatedCache[videoId] = _Cached(songs);
      return songs;
    } catch (e) {
      debugPrint('Lấy đề xuất cho $videoId thất bại: $e');
      return const [];
    }
  }

  /// Gộp đề xuất của các bài [seeds] (xen kẽ để bài nào cũng góp phần), bỏ
  /// video quá dài và những bài trong [exclude]. Thiếu thì bù bằng tìm kiếm.
  Future<List<Song>> recommend(
    List<String> seeds, {
    required bool preferKaraoke,
    Set<String> exclude = const {},
    int limit = 30,
  }) async {
    final lists = await Future.wait(seeds.map(related));
    final seen = {...seeds, ...exclude};
    final merged = <Song>[];
    for (var i = 0;; i++) {
      var any = false;
      for (final list in lists) {
        if (i >= list.length) continue;
        any = true;
        final s = list[i];
        if (s.durationSec >= _minDurationSec &&
            s.durationSec <= _maxRecommendSec &&
            seen.add(s.videoId)) {
          merged.add(s);
        }
      }
      if (!any) break;
    }

    var result = merged;
    if (preferKaraoke) {
      final karaoke = merged.where((s) => _karaokeTitle.hasMatch(s.title));
      if (karaoke.length >= 6) result = karaoke.toList();
    }
    if (result.length >= 6) return result.take(limit).toList();

    try {
      final more = await search(
        fallbackRecommendQuery,
        preferKaraoke: preferKaraoke,
      );
      return [...result, ...more.where((s) => seen.add(s.videoId))]
          .take(limit)
          .toList();
    } catch (_) {
      return result;
    }
  }

  /// Bóc danh sách video từ phản hồi của `youtubei/v1/next`.
  @visibleForTesting
  static List<Song> parseNextResponse(Object? json) {
    final lockups = <Map<String, dynamic>>[];
    void walk(Object? node) {
      if (node is List) {
        for (final e in node) {
          walk(e);
        }
      } else if (node is Map<String, dynamic>) {
        final lockup = node['lockupViewModel'];
        if (lockup is Map<String, dynamic>) {
          lockups.add(lockup);
          return;
        }
        for (final v in node.values) {
          walk(v);
        }
      }
    }

    walk(json);

    final songs = <Song>[];
    for (final l in lockups) {
      if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') continue;
      final id = l['contentId'];
      if (id is! String || id.isEmpty) continue;

      final meta = _path(l, ['metadata', 'lockupMetadataViewModel']);
      final title = _path(meta, ['title', 'content']);
      if (title is! String) continue;

      final rows = _path(meta, [
        'metadata',
        'contentMetadataViewModel',
        'metadataRows',
      ]);
      final parts = <Map<String, dynamic>>[
        if (rows is List)
          for (final r in rows)
            if (r is Map && r['metadataParts'] is List)
              for (final p in r['metadataParts'] as List)
                if (p is Map<String, dynamic>) p,
      ];
      String? text(Map<String, dynamic> p) => _path(p, ['text', 'content']) as String?;
      String? label(Map<String, dynamic> p) =>
          (p['accessibilityLabel'] as String?) ?? text(p);

      final channel = parts.isEmpty ? '' : text(parts.first) ?? '';
      String? views;
      String? published;
      for (final p in parts.skip(1)) {
        final what = label(p) ?? '';
        if (what.contains('lượt xem') || what.contains('views')) {
          views ??= text(p);
        } else if (what.contains('trước') || what.contains('ago')) {
          published ??= text(p);
        }
      }

      String? badge;
      void findBadge(Object? node) {
        if (badge != null) return;
        if (node is List) {
          node.forEach(findBadge);
        } else if (node is Map) {
          final b = node['thumbnailBadgeViewModel'];
          if (b is Map && b['text'] is String) {
            badge = b['text'] as String;
            return;
          }
          node.values.forEach(findBadge);
        }
      }

      findBadge(l['contentImage']);

      songs.add(Song(
        videoId: id,
        title: title,
        channel: channel,
        durationSec: parseDurationText(badge),
        thumbUrl: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        viewCount: parseCompactCount(views),
        publishedText: published,
      ));
    }
    return songs;
  }

  /// "24 N" → 24000, "2,2 Tr" → 2200000, "1,1 T" → 1100000000.
  @visibleForTesting
  static int? parseCompactCount(String? text) {
    if (text == null) return null;
    final m = RegExp(r'([\d.,]+)\s*(N|Tr|T|K|M|B)?', caseSensitive: false)
        .firstMatch(text.trim());
    if (m == null) return null;
    final unit = (m.group(2) ?? '').toLowerCase();
    // Có đơn vị thì dấu phẩy là phần thập phân; không có thì là dấu nghìn.
    final digits = unit.isEmpty
        ? m.group(1)!.replaceAll(RegExp(r'[.,]'), '')
        : m.group(1)!.replaceAll('.', '').replaceAll(',', '.');
    final n = double.tryParse(digits);
    if (n == null) return null;
    const scale = {
      'n': 1e3,
      'k': 1e3,
      'tr': 1e6,
      'm': 1e6,
      't': 1e9,
      'b': 1e9,
    };
    return (n * (scale[unit] ?? 1)).round();
  }

  static Object? _path(Object? node, List<String> keys) {
    var cur = node;
    for (final k in keys) {
      if (cur is! Map) return null;
      cur = cur[k];
    }
    return cur;
  }

  void dispose() {
    _yt.close();
    _http.close();
  }

  /// Chuyển "3:45" / "1:02:30" thành số giây.
  @visibleForTesting
  static int parseDurationText(String? text) {
    if (text == null || text.isEmpty) return 0;
    final parts = text.split(':').map((p) => int.tryParse(p.trim())).toList();
    if (parts.any((p) => p == null)) return 0;
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p!;
    }
    return seconds;
  }

  static final _agoPattern = RegExp(
    r'(\d+)\s*(years?|y|months?|mo|weeks?|w|days?|d|hours?|h|minutes?|min|m|seconds?|s)\s+ago',
    caseSensitive: false,
  );

  static const _agoUnits = {
    'y': 'năm',
    'mo': 'tháng',
    'w': 'tuần',
    'd': 'ngày',
    'h': 'giờ',
    'm': 'phút',
    's': 'giây',
  };

  /// Đổi "9y ago" / "3 months ago" mà thư viện trả về thành "9 năm trước" /
  /// "3 tháng trước" như YouTube tiếng Việt. Không nhận ra thì giữ nguyên.
  @visibleForTesting
  static String? localizeUploadDate(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = _agoPattern.firstMatch(text);
    if (match == null) return text;
    final unit = match.group(2)!.toLowerCase();
    final key = unit.startsWith('mo')
        ? 'mo'
        : unit.startsWith('mi')
            ? 'm'
            : unit[0];
    final vi = _agoUnits[key];
    if (vi == null) return text;
    final prefix = text.toLowerCase().startsWith('streamed')
        ? 'Đã phát trực tiếp '
        : '';
    return '$prefix${match.group(1)} $vi trước';
  }

  /// Giữ lại video hát được: bỏ livestream, Shorts, mục không phải video.
  @visibleForTesting
  static bool isSingable({required int durationSec, required bool isLive}) =>
      !isLive && durationSec >= _minDurationSec;
}

/// Một chuỗi trang kết quả của cùng một từ khoá, để "cuộn vô hạn" không phải
/// tìm lại từ đầu.
class _SearchSession {
  _SearchSession(this.query, this._yt);

  final String query;
  final yt.YoutubeExplode _yt;

  final List<List<Song>> _pages = [];
  yt.SearchList? _last;
  bool _exhausted = false;
  DateTime _fetchedAt = DateTime.now();
  Future<void>? _inFlight;

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(_fetchedAt) > ttl;

  Future<List<Song>> page(int index) async {
    while (_pages.length <= index && !_exhausted) {
      await (_inFlight ??= _fetchNext()).whenComplete(() => _inFlight = null);
    }
    return index < _pages.length ? _pages[index] : const [];
  }

  Future<void> _fetchNext() async {
    try {
      final yt.SearchList? list;
      if (_last == null) {
        list = await _yt.search
            .searchContent(query, filter: yt.TypeFilters.video);
      } else {
        list = await _last!.nextPage();
      }

      if (list == null) {
        _exhausted = true;
        return;
      }
      _last = list;
      _fetchedAt = DateTime.now();

      final songs = <Song>[];
      for (final result in list) {
        if (result is! yt.SearchVideo) continue;
        final durationSec = YoutubeService.parseDurationText(result.duration);
        if (!YoutubeService.isSingable(
          durationSec: durationSec,
          isLive: result.isLive,
        )) {
          continue;
        }
        if (result.title.toLowerCase().contains('#shorts')) continue;

        songs.add(Song(
          videoId: result.id.value,
          title: result.title,
          channel: result.author,
          durationSec: durationSec,
          thumbUrl: _bestThumb(result),
          viewCount: result.viewCount,
          publishedText: YoutubeService.localizeUploadDate(result.uploadDate),
        ));
      }

      if (songs.isEmpty && list.isEmpty) {
        _exhausted = true;
        return;
      }
      _pages.add(songs);
    } catch (e) {
      debugPrint('Tìm kiếm "$query" thất bại: $e');
      _exhausted = true;
      rethrow;
    }
  }

  static String _bestThumb(yt.SearchVideo v) {
    if (v.thumbnails.isEmpty) return Song.thumbnailFor(v.id.value);
    // Ảnh cuối danh sách là bản to nhất.
    return v.thumbnails.last.url.toString();
  }
}

class _Cached<T> {
  _Cached(this.value) : at = DateTime.now();

  final T value;
  final DateTime at;

  bool isExpired(Duration ttl) => DateTime.now().difference(at) > ttl;
}
