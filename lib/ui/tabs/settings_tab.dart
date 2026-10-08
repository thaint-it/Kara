import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/room_settings.dart';
import '../app.dart';
import '../pair_tv_page.dart';
import '../theme.dart';
import '../widgets/kara_card.dart';
import '../widgets/qr_panel.dart';

/// Tab "Cài đặt": chế độ phát, TV đã ghép, và các tuỳ chọn ở mục 3.
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final s = room.settings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        const Text(
          'Cài đặt',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),

        if (Platform.isIOS) ...[
          const _IosHostNotice(),
          const SizedBox(height: 18),
        ],

        _section('Chế độ phát'),
        KaraCard(
          child: Column(
            children: [
              // Tự vẽ ô chọn thay vì dùng `RadioListTile`: API `groupValue` /
              // `onChanged` của nó bị thay bằng `RadioGroup` ở Flutter 3.32.
              for (final mode in PlaybackMode.values)
                ListTile(
                  onTap: () => room.setMode(mode),
                  leading: Icon(
                    s.mode == mode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: s.mode == mode
                        ? KaraColors.accent
                        : KaraColors.muted,
                  ),
                  title: Text(mode.label, style: const TextStyle(fontSize: 16)),
                  subtitle: Text(
                    mode == PlaybackMode.tv
                        ? 'Điều khiển app YouTube trên Smart TV qua WiFi'
                        : 'Phát ngay trên máy này, âm ra loa qua Bluetooth hoặc dây',
                    style: const TextStyle(fontSize: 15, color: KaraColors.muted),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        _section('TV đã ghép'),
        KaraCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text(room.tvLink.description),
                subtitle: room.tv.isPaired
                    ? const Text('Tự kết nối lại mỗi khi mở app')
                    : const Text('Chưa ghép TV nào'),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PairTvPage()),
                      ),
                      icon: const Icon(Icons.add_link, size: 20),
                      label: Text(room.tv.isPaired ? 'Ghép TV khác' : 'Ghép TV'),
                    ),
                  ),
                  if (room.tv.isPaired)
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _confirmForget(context),
                        icon: const Icon(Icons.link_off, size: 20),
                        label: const Text('Quên TV này'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        _section('Duyệt bài'),
        KaraCard(
          child: Column(
            children: [
              SwitchListTile(
                value: s.autoApprove,
                onChanged: (v) =>
                    room.updateSettings(s.copyWith(autoApprove: v)),
                title: const Text('Tự động duyệt'),
                subtitle: const Text('Mọi yêu cầu vào thẳng hàng chờ'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                value: s.guestControl,
                onChanged: (v) =>
                    room.updateSettings(s.copyWith(guestControl: v)),
                title: const Text('Cho khách điều khiển'),
                subtitle: const Text('Khách được bấm Qua bài / Tạm dừng'),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Giới hạn bài đang chờ mỗi khách'),
                subtitle: Text('Hiện tại: ${s.maxPendingPerGuest} bài'),
                trailing: SizedBox(
                  width: 128,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: s.maxPendingPerGuest <= 1
                            ? null
                            : () => room.updateSettings(s.copyWith(
                                  maxPendingPerGuest: s.maxPendingPerGuest - 1,
                                )),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '${s.maxPendingPerGuest}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: s.maxPendingPerGuest >= 10
                            ? null
                            : () => room.updateSettings(s.copyWith(
                                  maxPendingPerGuest: s.maxPendingPerGuest + 1,
                                )),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        _section('Buổi hát'),
        const _SessionCard(),

        const SizedBox(height: 18),
        _section('Quảng cáo'),
        KaraCard(
          child: SwitchListTile(
            value: s.autoSkipAds,
            onChanged: (v) => room.updateSettings(s.copyWith(autoSkipAds: v)),
            title: const Text('Tự bỏ qua quảng cáo'),
            subtitle: const Text(
              'Quảng cáo trên TV vừa cho bỏ qua là tự bấm "Bỏ qua". '
              'Quảng cáo không bỏ qua được thì vẫn phải chờ.',
            ),
          ),
        ),

        const SizedBox(height: 18),
        _section('Tìm kiếm'),
        KaraCard(
          child: SwitchListTile(
            value: s.preferKaraoke,
            onChanged: (v) => room.updateSettings(s.copyWith(preferKaraoke: v)),
            title: const Text('Ưu tiên bản karaoke'),
            subtitle: const Text(
              'Tự thêm chữ "karaoke" vào từ khoá nếu bạn chưa gõ',
            ),
          ),
        ),

        const SizedBox(height: 18),
        _section('Khách trong phòng'),
        if (room.guests.isEmpty)
          const KaraCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chưa có khách nào vào phòng.',
                style: TextStyle(fontSize: 16, color: KaraColors.muted),
              ),
            ),
          )
        else
          KaraCard(
            child: Column(
              children: [
                for (final guest in room.guests)
                  SwitchListTile(
                    value: guest.trusted,
                    onChanged: (v) => room.setGuestTrusted(guest.id, v),
                    title: Text(guest.name),
                    subtitle: const Text('Tin tưởng khách này (tự duyệt)'),
                  ),
              ],
            ),
          ),

        const SizedBox(height: 18),
        _section('Mã QR cho khách'),
        const QrPanel(),
      ],
    );
  }

  static Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 15,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: KaraColors.muted,
          ),
        ),
      );

  Future<void> _confirmForget(BuildContext context) async {
    final room = RoomScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KaraColors.surface,
        title: const Text('Quên TV này?'),
        content: const Text(
          'Lần sau bạn sẽ phải nhập lại mã 12 số trên TV.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quên'),
          ),
        ],
      ),
    );
    if (ok == true) room.tv.forget();
  }
}

/// iOS không cho app chạy web server khi màn hình đã tắt (mục 13 của đặc tả).
/// Đây là giới hạn của hệ điều hành, không phải lỗi app, nên nói thẳng cho chủ
/// phòng biết thay vì để họ tự đoán vì sao khách mất kết nối.
class _IosHostNotice extends StatelessWidget {
  const _IosHostNotice();

  @override
  Widget build(BuildContext context) => const KaraCard(
        color: KaraColors.accentWash,
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: KaraColors.accent),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Làm chủ phòng bằng iPhone',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'iOS không cho app chạy web server khi màn hình tắt. Hãy để '
                    'app mở trong lúc hát — app tự giữ màn hình sáng. Nếu khoá '
                    'máy hoặc chuyển sang app khác lâu, khách sẽ mất kết nối và '
                    'phải quét lại mã QR.\n\n'
                    'Muốn ổn định cả buổi thì dùng điện thoại Android làm chủ '
                    'phòng; iPhone vẫn làm khách bình thường.',
                    style: TextStyle(fontSize: 15, color: KaraColors.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Thông tin buổi hát đang diễn ra + cách kết thúc nó.
///
/// Đây là chỗ duy nhất người dùng xoá được hàng chờ của cả phòng, nên nói rõ
/// trước là sẽ xoá những gì thay vì chỉ đặt một cái nút trần.
class _SessionCard extends StatelessWidget {
  const _SessionCard();

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final s = room.settings;

    return KaraCard(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.celebration_outlined),
            title: Text('Bắt đầu ${_formatTime(room.sessionStartedAt)}'),
            subtitle: Text(
              room.hasSessionContent
                  ? 'Đang có ${room.queue.length} bài chờ, '
                      '${room.guests.length} khách'
                  : 'Hàng chờ đang trống',
            ),
          ),
          const Divider(height: 1),

          ListTile(
            title: const Text('Tự kết thúc khi không dùng'),
            subtitle: Text(
              s.sessionIdleHours > 0
                  ? 'Sau ${s.sessionIdleHours} giờ không có bài nào được phát '
                      'và không ai gửi yêu cầu'
                  : 'Không bao giờ tự kết thúc',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                for (final hours in RoomSettings.idleHourChoices)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: s.sessionIdleHours == hours,
                      onSelected: (_) => room.updateSettings(
                        s.copyWith(sessionIdleHours: hours),
                      ),
                      label: Text(hours == 0 ? 'Không' : '$hours giờ'),
                      labelStyle: const TextStyle(fontSize: 15),
                      selectedColor: KaraColors.accent,
                      backgroundColor: KaraColors.surfaceHigh,
                      side: const BorderSide(color: KaraColors.line),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.tv_off, color: KaraColors.muted),
            title: const Text('TV mất kết nối quá 2 giờ'),
            subtitle: Text(
              room.tvOfflineSince == null
                  ? 'Buổi hát cũng kết thúc, nhưng chỉ khi hàng chờ đã trống'
                  : 'TV đang mất kết nối từ ${_formatTime(room.tvOfflineSince!)}',
              style: TextStyle(
                fontSize: 15,
                color: room.tvOfflineSince == null
                    ? KaraColors.muted
                    : KaraColors.warn,
              ),
            ),
          ),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => _confirmEnd(context),
              icon: const Icon(Icons.stop_circle_outlined, size: 20),
              label: const Text('Kết thúc buổi hát'),
              style: OutlinedButton.styleFrom(
                foregroundColor: KaraColors.accent,
                side: const BorderSide(color: KaraColors.accent),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime at) {
    final hhmm = '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay
        ? '$hhmm hôm nay'
        : '$hhmm ngày ${at.day}/${at.month}';
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final room = RoomScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KaraColors.surface,
        title: const Text('Kết thúc buổi hát?'),
        content: const Text(
          'Sẽ xoá hàng chờ, các yêu cầu chờ duyệt và danh sách khách, rồi sinh '
          'mã phòng mới — khách phải quét lại mã QR.\n\n'
          'Vẫn giữ: cài đặt, TV đã ghép, lịch sử Đã hát và những khách bạn đã '
          'tin tưởng.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kết thúc'),
          ),
        ],
      ),
    );
    if (ok == true) await room.endSession();
  }
}
