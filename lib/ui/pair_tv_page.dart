import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../lounge/tv_controller.dart';
import '../models/room_settings.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets/kara_card.dart';

/// Ghép nối TV bằng mã 12 số (mục 5.1 + 7.1).
class PairTvPage extends StatefulWidget {
  const PairTvPage({super.key});

  @override
  State<PairTvPage> createState() => _PairTvPageState();
}

class _PairTvPageState extends State<PairTvPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Mã trên TV hiện dạng "123 456 789 012" – bỏ hết khoảng trắng.
  String get _digits => _code.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _pair() async {
    if (_digits.length != 12) {
      setState(() => _error = 'Mã phải đủ 12 số.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final room = RoomScope.read(context);
    try {
      await room.tv.pairWithCode(_digits);
      // Ghép TV xong thì chuyển luôn sang chế độ phát trên TV.
      if (room.mode != PlaybackMode.tv) await room.setMode(PlaybackMode.tv);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã ghép TV. Lần sau app tự kết nối.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is TvPairingException
            ? e.message
            : 'Không ghép được. Kiểm tra TV và WiFi rồi thử lại.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ghép nối TV')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          const KaraCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trên TV, mở app YouTube rồi vào:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 10),
                  _Step(1, 'Cài đặt (bánh xe ở menu bên trái)'),
                  _Step(2, 'Liên kết với TV bằng mã'),
                  _Step(3, 'Đọc mã 12 số hiện trên TV'),
                  SizedBox(height: 10),
                  Text(
                    'Điện thoại và TV phải dùng cùng một WiFi.',
                    style: TextStyle(fontSize: 15, color: KaraColors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ],
            style: const TextStyle(
              fontSize: 26,
              letterSpacing: 4,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              hintText: '000000000000',
              hintStyle: TextStyle(
                fontSize: 26,
                letterSpacing: 4,
                color: KaraColors.line,
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _pair(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 15, color: KaraColors.accent),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Ghép nối'),
          ),
          const SizedBox(height: 24),
          _StatusRow(link: room.tvLink),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              await room.setMode(PlaybackMode.phone);
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.smartphone, size: 20),
            label: const Text('Không có TV – phát trên điện thoại này'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$number. ',
              style: const TextStyle(fontSize: 16, color: KaraColors.muted),
            ),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
          ],
        ),
      );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.link});

  final TvLink link;

  @override
  Widget build(BuildContext context) {
    final color = switch (link.state) {
      TvLinkState.connected => KaraColors.ok,
      TvLinkState.connecting => KaraColors.warn,
      TvLinkState.unpaired => KaraColors.muted,
      TvLinkState.disconnected => KaraColors.accent,
      TvLinkState.released => KaraColors.muted,
    };

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            link.description,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }
}
