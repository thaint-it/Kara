import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../app.dart';
import '../theme.dart';

/// Thanh thời gian kéo được để tua, kèm nút lùi / tới 10 giây – hát chậm hơn
/// nhạc thì lùi lại một đoạn.
///
/// Trong lúc kéo, số giây hiện theo ngón tay; thả tay mới gửi lệnh tua để TV
/// không phải nhận hàng chục lệnh liên tiếp.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.compact = false});

  /// Bản gọn cho trình phát toàn màn hình: không có nút ±10 giây.
  final bool compact;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  /// Vị trí đang kéo (giây); `null` khi không kéo.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final duration = room.duration;
    final enabled = room.current != null && duration > 0 && !room.isAd;
    final position =
        (_dragging ?? room.position).clamp(0.0, duration > 0 ? duration : 0.0);

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        activeTrackColor: KaraColors.accent,
        inactiveTrackColor: KaraColors.line,
        thumbColor: KaraColors.accent,
        overlayColor: KaraColors.accentSoft,
        disabledActiveTrackColor: KaraColors.line,
        disabledInactiveTrackColor: KaraColors.line,
        disabledThumbColor: Colors.transparent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        min: 0,
        max: duration > 0 ? duration : 1,
        value: duration > 0 ? position : 0,
        onChanged: enabled ? (v) => setState(() => _dragging = v) : null,
        onChangeEnd: enabled
            ? (v) {
                room.seekTo(v);
                setState(() => _dragging = null);
              }
            : null,
      ),
    );

    final times = Row(
      children: [
        Text(
          // formatDuration(0) ra "--:--" (chưa biết thời lượng); vị trí đầu
          // bài thì phải là "0:00".
          enabled && position < 1 ? '0:00' : formatDuration(position.round()),
          style: TextStyle(
            fontSize: 15,
            color: _dragging != null ? KaraColors.text : KaraColors.muted,
            fontWeight: _dragging != null ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        if (!widget.compact) ...[
          _JumpButton(
            label: '10 giây',
            icon: Icons.replay_10,
            tooltip: 'Lùi 10 giây',
            onPressed: enabled ? () => room.seekBy(-10) : null,
          ),
          const SizedBox(width: 8),
          _JumpButton(
            label: '10 giây',
            icon: Icons.forward_10,
            tooltip: 'Tới 10 giây',
            onPressed: enabled ? () => room.seekBy(10) : null,
          ),
          const Spacer(),
        ],
        Text(
          formatDuration(duration.round()),
          style: const TextStyle(fontSize: 15, color: KaraColors.muted),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 32, child: slider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: times,
        ),
      ],
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            foregroundColor: KaraColors.text,
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          icon: Icon(icon, size: 24),
          label: Text(label),
        ),
      );
}
