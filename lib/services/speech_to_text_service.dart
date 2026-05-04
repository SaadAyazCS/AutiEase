import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// App-wide speech-to-text. Safe to inject or call via [instance]; the
/// underlying engine is shared so only one listen session should run at a time.
class SpeechToTextService {
  SpeechToTextService._();
  static final SpeechToTextService instance = SpeechToTextService._();
  factory SpeechToTextService() => instance;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;

  bool get isInitialized => _available;

  /// Initializes the recognizer and requests OS permission when needed.
  Future<bool> initialize() async {
    _available = await _speech.initialize(
      onError: (e) => debugPrint('STT error: $e'),
      onStatus: (s) => debugPrint('STT status: $s'),
    );
    return _available;
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {}
  }

  /// Listens until final result, error, or [timeout].
  Future<String?> listenOnce({
    Duration timeout = const Duration(seconds: 10),
    Duration pauseFor = const Duration(seconds: 3),
  }) async {
    if (!_available) {
      final ok = await initialize();
      if (!ok) {
        return null;
      }
    }

    final buffer = StringBuffer();
    final resultCompleter = Completer<String?>();
    Timer? timeoutTimer;
    var finished = false;

    void complete([String? value]) {
      if (finished) {
        return;
      }
      finished = true;
      timeoutTimer?.cancel();
      if (!resultCompleter.isCompleted) {
        resultCompleter.complete(value);
      }
    }

    timeoutTimer = Timer(timeout, () async {
      await stop();
      final text = buffer.toString().trim();
      complete(text.isEmpty ? null : text);
    });

    try {
      await _speech.listen(
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            buffer.clear();
            buffer.write(result.recognizedWords);
          }
          if (result.finalResult) {
            final text = result.recognizedWords.trim();
            complete(text.isEmpty ? null : text);
          }
        },
        pauseFor: pauseFor,
        listenFor: timeout,
        onSoundLevelChange: (_) {},
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          cancelOnError: false,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('listenOnce: $e');
      complete(null);
    }

    return resultCompleter.future;
  }
}
