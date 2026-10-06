import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app.dart';
import '../theme.dart';
import 'kara_card.dart';

/// Mã QR thu gọn trên tab Phòng; bấm để phóng to cho khách quét (mục 11).
class QrPanel extends StatelessWidget {
  const QrPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final room = RoomScope.of(context);
    final url = room.guestUrl;

    if (url == null) {
      return const KaraCard(
        padding: EdgeInsets.all(16),
        child: Text(
          'Chưa bật được web server cho khách. Kiểm tra WiFi rồi mở lại app.',
          style: TextStyle(fontSize: 16, color: KaraColors.muted),
        ),
      );
    }

    return KaraCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showQrDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: url.toString(),
                  version: QrVersions.auto,
                  size: 72,
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Khách quét mã này để chọn bài',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      url.toString(),
                      style: const TextStyle(fontSize: 15, color: KaraColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mã phòng: ${room.roomCode}',
                      style: const TextStyle(fontSize: 15, color: KaraColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_full, color: KaraColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mã QR cỡ lớn, kèm địa chỉ để khách tự gõ khi không quét được.
Future<void> showQrDialog(BuildContext context) async {
  final room = RoomScope.read(context);
  final url = room.guestUrl;
  if (url == null) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: KaraColors.surface,
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Quét để chọn bài',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: url.toString(),
                version: QrVersions.auto,
                size: 260,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              url.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Mã phòng ${room.roomCode} • phải cùng WiFi',
              style: const TextStyle(fontSize: 15, color: KaraColors.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url.toString()));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Đã chép địa chỉ')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Chép địa chỉ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Xong'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
