import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme.dart';

/// Mở màn hình "Đang nghe…" giống nút micro của YouTube.
///
/// Trả về câu người dùng vừa nói, hoặc `null` nếu huỷ / không nghe được gì.
Future<String?> showVoiceSearch(BuildContext context) => showGeneralDialog<String>(
      context: context,
      barrierLabel: 'Tìm bằng giọng nói',
      barrierColor: KaraColors.bg,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => const _VoiceSearchView(),
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );

enum _Phase { starting, listening, notHeard, unavailable }

class _VoiceSearchView extends StatefulWidget {
  const _VoiceSearchView();

  @override
  State<_VoiceSearchView> createState() => _VoiceSearchViewState();
}

class _VoiceSearchViewState extends State<_VoiceSearchView>
    with SingleTickerProviderStateMixin {
  /// Plugin là singleton, khởi tạo một lần cho cả app.
  static final _speech = SpeechToText();

  /// Locale tiếng Việt của bộ nhận giọng nói trên máy, tra một lần.
  static String? _viLocale;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  _Phase _phase = _Phase.starting;
  String _text = '';
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _speech.errorListener = null;
    _speech.statusListener = null;
    if (_speech.isListening) _speech.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.starting;
      _text = '';
    });

    bool ready;
    try {
      ready = await _speech.initialize();
    } catch (e) {
      debugPrint('Không khởi tạo được nhận giọng nói: $e');
      ready = false;
    }
    if (!mounted) return;
    if (!ready) {
      setState(() => _phase = _Phase.unavailable);
      return;
    }

    // `initialize` chỉ nhận listener ở lần đầu, nên gán lại cho màn hình này.
    _speech.errorListener = _onError;
    _speech.statusListener = _onStatus;

    _viLocale ??= await _findVietnamese();

    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        localeId: _viLocale,
        listenMode: ListenMode.search,
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
      ),
    );
    if (!mounted) return;
    setState(() => _phase = _Phase.listening);
    _pulse.repeat(reverse: true);
  }

  Future<String?> _findVietnamese() async {
    try {
      final locales = await _speech.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('vi')) return l.localeId;
      }
    } catch (_) {}
    // Không liệt kê được thì vẫn thử tiếng Việt; máy không có sẽ tự dùng mặc định.
    return 'vi_VN';
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _text = result.recognizedWords);
    if (result.finalResult) _finish();
  }

  void _onStatus(String status) {
    if (!mounted) return;
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _pulse.stop();
      // Kết quả cuối có thể đến sau trạng thái "done" một chút.
      Timer(const Duration(milliseconds: 400), () {
        if (mounted && !_closing && _text.trim().isEmpty) {
          setState(() => _phase = _Phase.notHeard);
        }
      });
    }
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('Nhận giọng nói lỗi: ${error.errorMsg}');
    if (!mounted || _closing) return;
    _pulse.stop();
    setState(() {
      _phase = error.errorMsg.contains('permission')
          ? _Phase.unavailable
          : _Phase.notHeard;
    });
  }

  void _finish() {
    final q = _text.trim();
    if (_closing || q.isEmpty) return;
    _closing = true;
    _pulse.stop();
    // Dừng một nhịp cho người dùng kịp thấy chữ vừa nói, như YouTube.
    Timer(const Duration(milliseconds: 350), () {
      if (mounted) Navigator.of(context).pop(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String headline;
    switch (_phase) {
      case _Phase.starting:
        headline = 'Đang chuẩn bị…';
      case _Phase.listening:
        headline = _text.isEmpty ? 'Đang nghe…' : _text;
      case _Phase.notHeard:
        headline = 'Không nghe rõ. Bấm micro để nói lại.';
      case _Phase.unavailable:
        headline = 'Máy này chưa tìm bằng giọng nói được.\n'
            'Cần cho phép micro và có ứng dụng Google.';
    }

    return Material(
      color: KaraColors.bg,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Đóng',
                iconSize: 28,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Align(
                  alignment: const Alignment(-1, -0.4),
                  child: Text(
                    headline,
                    style: TextStyle(
                      fontSize: _phase == _Phase.listening && _text.isNotEmpty
                          ? 30
                          : 24,
                      fontWeight: FontWeight.w600,
                      color: _phase == _Phase.listening && _text.isNotEmpty
                          ? KaraColors.text
                          : KaraColors.muted,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
            _micButton(),
            const SizedBox(height: 16),
            Text(
              _phase == _Phase.listening ? 'Nói tên bài hoặc ca sĩ' : '',
              style: const TextStyle(fontSize: 15, color: KaraColors.muted),
            ),
            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }

  Widget _micButton() {
    final active = _phase == _Phase.listening;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final halo = active ? 96 + 36 * _pulse.value : 96.0;
        return SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: halo,
                height: halo,
                decoration: const BoxDecoration(
                  color: KaraColors.accentSoft,
                  shape: BoxShape.circle,
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: Material(
        color: active ? KaraColors.accent : KaraColors.surfaceHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: active ? _speech.stop : _start,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Icon(
              Icons.mic,
              size: 40,
              color: active ? Colors.white : KaraColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
