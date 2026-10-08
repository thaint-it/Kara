import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/room_controller.dart';
import '../../models/song.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/video_card.dart';
import '../widgets/voice_search.dart';

/// Tab "Tìm bài" của chủ phòng, bố cục theo app YouTube: ô tìm kiếm bo tròn +
/// nút micro, gợi ý khi gõ, kết quả ảnh to, cuộn vô hạn, dán link, nút
/// "Ưu tiên bản karaoke" (mục 6).
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  Timer? _debounce;
  List<String> _suggestions = const [];
  final List<Song> _results = [];

  String _query = '';
  int _page = 0;
  bool _loading = false;
  bool _done = false;
  String? _error;

  /// Bài đề xuất ở màn hình chưa tìm; `null` = chưa tải.
  List<Song>? _recommended;
  bool _recoLoading = false;

  /// Bài làm "hạt giống" cho lần đề xuất gần nhất. Hát sang bài khác thì tải
  /// lại để đề xuất bám theo bài vừa hát.
  String? _recoSeed;

  /// Thể loại bấm là tìm, cho người không nhớ tên bài.
  static const _genres = [
    ('Nhạc trẻ', 'nhạc trẻ hay nhất'),
    ('Bolero', 'bolero'),
    ('Nhạc vàng', 'nhạc vàng'),
    ('Song ca', 'song ca nam nữ'),
    ('Nhạc Trịnh', 'nhạc trịnh'),
    ('Remix', 'remix'),
    ('Nhạc Hoa lời Việt', 'nhạc hoa lời việt'),
    ('Thiếu nhi', 'thiếu nhi'),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  /// Gợi ý khi gõ, debounce 250 ms.
  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2 || q.contains('youtu')) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() {}); // cập nhật nút xoá / dán ở ô tìm kiếm
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final items = await RoomScope.read(context).youtube.suggest(q);
      // Gợi ý về muộn sau khi đã bấm tìm thì bỏ, kẻo che mất kết quả.
      if (!mounted || _input.text.trim() != q || _query == q) return;
      setState(() => _suggestions = items);
    });
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    FocusScope.of(context).unfocus();
    RoomScope.read(context).rememberSearch(q);
    setState(() {
      _query = q;
      _page = 0;
      _done = false;
      _error = null;
      _results.clear();
      _suggestions = const [];
      _loading = true;
    });

    await _fetch();
  }

  Future<void> _loadMore() async {
    if (_loading || _done || _query.isEmpty) return;
    setState(() => _loading = true);
    await _fetch();
  }

  Future<void> _fetch() async {
    final room = RoomScope.read(context);
    try {
      final page = await room.youtube.search(
        _query,
        page: _page,
        preferKaraoke: room.settings.preferKaraoke,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (page.isEmpty) {
          _done = true;
        } else {
          _page += 1;
          _results.addAll(page);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _done = true;
        _error = 'Không tìm được. Kiểm tra Internet rồi thử lại.';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _input.text = text;
    await _search(text);
  }

  Future<void> _voiceSearch() async {
    FocusScope.of(context).unfocus();
    final spoken = await showVoiceSearch(context);
    if (spoken == null || spoken.trim().isEmpty || !mounted) return;
    _input.text = spoken;
    await _search(spoken);
  }

  void _clear() => setState(() {
        _input.clear();
        _results.clear();
        _suggestions = const [];
        _query = '';
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 8),
              Material(
                color: KaraColors.surfaceHigh,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Tìm bằng giọng nói',
                  iconSize: 26,
                  padding: const EdgeInsets.all(12),
                  onPressed: _voiceSearch,
                  icon: const Icon(Icons.mic, color: KaraColors.text),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Ưu tiên bản karaoke'),
              labelStyle: const TextStyle(fontSize: 15),
              avatar: const Icon(Icons.mic_external_on, size: 18),
              selected: room.settings.preferKaraoke,
              showCheckmark: false,
              selectedColor: KaraColors.text,
              checkmarkColor: KaraColors.bg,
              shape: const StadiumBorder(),
              onSelected: (v) {
                room.updateSettings(room.settings.copyWith(preferKaraoke: v));
                if (_query.isNotEmpty) _search(_query);
              },
            ),
          ),
        ),
        Expanded(
          child: _suggestions.isNotEmpty ? _suggestionList() : _body(),
        ),
      ],
    );
  }

  /// Ô tìm kiếm bo tròn hai đầu như thanh tìm kiếm của YouTube.
  Widget _searchField() {
    const pill = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(999)),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: _input,
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
      onSubmitted: _search,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        hintText: 'Tìm trên YouTube',
        border: pill,
        enabledBorder: pill,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(999)),
          borderSide: BorderSide(color: KaraColors.muted),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        prefixIcon: const Icon(Icons.search, color: KaraColors.muted),
        suffixIcon: _input.text.isNotEmpty
            ? IconButton(
                tooltip: 'Xoá',
                onPressed: _clear,
                icon: const Icon(Icons.close, color: KaraColors.text),
              )
            : IconButton(
                tooltip: 'Dán link YouTube',
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste, color: KaraColors.muted),
              ),
      ),
    );
  }

  /// Gợi ý chiếm cả màn hình khi đang gõ, mỗi dòng có mũi tên ↖ để đưa gợi ý
  /// lên ô tìm kiếm mà chưa tìm ngay — giống YouTube.
  Widget _suggestionList() => ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: _suggestions.length,
        itemBuilder: (context, i) {
          final text = _suggestions[i];
          return ListTile(
            leading: const Icon(Icons.search, color: KaraColors.text),
            title: Text(text, style: const TextStyle(fontSize: 17)),
            trailing: IconButton(
              tooltip: 'Sửa từ khoá này',
              onPressed: () {
                _input.value = TextEditingValue(
                  text: '$text ',
                  selection: TextSelection.collapsed(offset: text.length + 1),
                );
                _onChanged(_input.text);
              },
              icon: Transform.rotate(
                angle: -0.785398, // -45°: mũi tên chéo lên trái
                child: const Icon(Icons.arrow_upward, color: KaraColors.muted),
              ),
            ),
            onTap: () {
              _input.text = text;
              _search(text);
            },
          );
        },
      );

  Widget _body() {
    if (_error != null && _results.isEmpty) {
      return EmptyHint(icon: Icons.wifi_off, message: _error!);
    }
    if (_results.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty && _query.isEmpty) return _home();
    if (_results.isEmpty) {
      return const EmptyHint(
        icon: Icons.search_off,
        message: 'Không tìm thấy bài nào.',
      );
    }

    final room = RoomScope.of(context);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: _results.length + 1,
      itemBuilder: (context, index) {
        if (index == _results.length) {
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _done
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'Hết kết quả',
                      style: TextStyle(fontSize: 15, color: KaraColors.muted),
                    ),
                  ),
                )
              : const SizedBox(height: 40);
        }

        final song = _results[index];

        return VideoCard(
          song: song,
          tags: [
            if (room.isDuplicate(song.videoId))
              const KaraTag('Đã có trong hàng chờ', color: KaraColors.ok),
            if (room.phoneTarget.blockedVideoIds.contains(song.videoId))
              const KaraTag('Không nhúng được', color: KaraColors.warn),
          ],
          onTap: () => _showActions(song),
        );
      },
    );
  }

  // ------------------------------------------- màn hình khi chưa tìm gì

  Future<void> _loadRecommendations() async {
    final room = RoomScope.read(context);
    final seed = _seedKey(room);
    setState(() {
      _recoLoading = true;
      _recoSeed = seed;
    });
    List<Song> songs;
    try {
      songs = await room.recommendations();
    } catch (_) {
      songs = const [];
    }
    if (!mounted) return;
    setState(() {
      _recommended = songs;
      _recoLoading = false;
    });
  }

  static String _seedKey(RoomController room) =>
      room.current?.song.videoId ??
      room.recentlySung(limit: 1).firstOrNull?.videoId ??
      '';

  Widget _home() {
    final room = RoomScope.of(context);
    final history = room.searchHistory.take(6).toList();
    final sung = room.recentlySung();

    if (!_recoLoading && (_recommended == null || _recoSeed != _seedKey(room))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_recoLoading) _loadRecommendations();
      });
    }

    return RefreshIndicator(
      onRefresh: _loadRecommendations,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (history.isNotEmpty) ...[
            const _SectionTitle('Tìm gần đây'),
            for (final q in history)
              ListTile(
                leading: const Icon(Icons.history, color: KaraColors.text),
                title: Text(q, style: const TextStyle(fontSize: 17)),
                trailing: IconButton(
                  tooltip: 'Xoá khỏi lịch sử',
                  onPressed: () => room.forgetSearch(q),
                  icon: const Icon(Icons.close, color: KaraColors.muted),
                ),
                onTap: () {
                  _input.text = q;
                  _search(q);
                },
              ),
          ],
          const _SectionTitle('Thể loại'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, query) in _genres)
                  ActionChip(
                    label: Text(label),
                    labelStyle: const TextStyle(fontSize: 15),
                    backgroundColor: KaraColors.surfaceHigh,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onPressed: () {
                      _input.text = query;
                      _search(query);
                    },
                  ),
              ],
            ),
          ),
          if (sung.isNotEmpty) ...[
            const _SectionTitle('Hát lại'),
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sung.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _MiniCard(
                  song: sung[i],
                  onTap: () => _showActions(sung[i]),
                ),
              ),
            ),
          ],
          _SectionTitle(sung.isEmpty && room.current == null
              ? 'Karaoke đang hot'
              : 'Gợi ý cho bạn'),
          if (_recommended == null || (_recoLoading && _recommended!.isEmpty))
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recommended!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Chưa lấy được bài gợi ý.',
                    style: TextStyle(fontSize: 16, color: KaraColors.muted),
                  ),
                  TextButton(
                    onPressed: _loadRecommendations,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            )
          else
            for (final song in _recommended!)
              VideoCard(
                song: song,
                tags: [
                  if (room.isDuplicate(song.videoId))
                    const KaraTag('Đã có trong hàng chờ', color: KaraColors.ok),
                ],
                onTap: () => _showActions(song),
              ),
        ],
      ),
    );
  }

  /// Bảng chọn bật lên từ dưới khi bấm vào bài, như menu ⋮ của YouTube.
  void _showActions(Song song) {
    final room = RoomScope.read(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KaraColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: KaraColors.text),
              title: const Text('Thêm vào hàng chờ',
                  style: TextStyle(fontSize: 17)),
              onTap: () {
                Navigator.pop(ctx);
                room.addByHost(song);
                _snack('Đã thêm "${song.title}"');
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.vertical_align_top, color: KaraColors.text),
              title: const Text('Hát ngay sau bài này',
                  style: TextStyle(fontSize: 17)),
              onTap: () {
                Navigator.pop(ctx);
                room.addByHost(song, priority: true);
                _snack('Sẽ hát ngay sau bài này');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      );
}

/// Thẻ nhỏ cho hàng cuộn ngang "Hát lại".
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SongThumb(song: song, width: 200),
              const SizedBox(height: 8),
              Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      );
}
