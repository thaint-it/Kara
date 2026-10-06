import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/song.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets/song_tile.dart';

/// Tab "Tìm bài" của chủ phòng: gợi ý khi gõ, cuộn vô hạn, dán link, công tắc
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
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final items = await RoomScope.read(context).youtube.suggest(q);
      if (mounted) setState(() => _suggestions = items);
    });
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;

    FocusScope.of(context).unfocus();
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

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            children: [
              TextField(
                controller: _input,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Tên bài, ca sĩ, hoặc dán link YouTube',
                  prefixIcon: const Icon(Icons.search, color: KaraColors.muted),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Dán link',
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste,
                            color: KaraColors.muted),
                      ),
                      if (_input.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Xoá',
                          onPressed: () => setState(() {
                            _input.clear();
                            _results.clear();
                            _suggestions = const [];
                            _query = '';
                            _error = null;
                          }),
                          icon: const Icon(Icons.close, color: KaraColors.muted),
                        ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Switch(
                    value: room.settings.preferKaraoke,
                    onChanged: (v) {
                      room.updateSettings(
                        room.settings.copyWith(preferKaraoke: v),
                      );
                      if (_query.isNotEmpty) _search(_query);
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Ưu tiên bản karaoke',
                      style: TextStyle(fontSize: 15, color: KaraColors.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty) _suggestionList(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _suggestionList() => Container(
        constraints: const BoxConstraints(maxHeight: 280),
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: KaraColors.surface,
          border: Border.all(color: KaraColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => ListTile(
            dense: false,
            leading: const Icon(Icons.search, size: 20),
            title: Text(_suggestions[i], style: const TextStyle(fontSize: 16)),
            onTap: () {
              _input.text = _suggestions[i];
              _search(_suggestions[i]);
            },
          ),
        ),
      );

  Widget _body() {
    if (_error != null && _results.isEmpty) {
      return EmptyHint(icon: Icons.wifi_off, message: _error!);
    }
    if (_results.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return const EmptyHint(
        icon: Icons.search,
        message: 'Gõ tên bài để tìm.\nDán link YouTube cũng được.',
      );
    }

    final room = RoomScope.of(context);

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: _results.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
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
        final duplicate = room.isDuplicate(song.videoId);

        return SongTile(
          song: song,
          tags: [
            if (duplicate)
              const KaraTag('Đã có trong hàng chờ', color: KaraColors.ok),
            if (room.phoneTarget.blockedVideoIds.contains(song.videoId))
              const KaraTag('Không nhúng được', color: KaraColors.warn),
          ],
          actions: [
            CompactButton(
              label: 'Thêm',
              icon: Icons.playlist_add,
              primary: true,
              onPressed: () {
                room.addByHost(song);
                _snack('Đã thêm "${song.title}"');
              },
            ),
            CompactButton(
              label: 'Ưu tiên',
              icon: Icons.vertical_align_top,
              onPressed: () {
                room.addByHost(song, priority: true);
                _snack('Sẽ hát ngay sau bài này');
              },
            ),
          ],
        );
      },
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
