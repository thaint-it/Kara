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

    final uri = Uri.parse(
      'https://suggestqueries.google.com/complete/search'
      '?client=youtube&ds=yt&hl=vi&q=${Uri.encodeQueryComponent(q)}',
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
          publishedText: result.uploadDate,
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
