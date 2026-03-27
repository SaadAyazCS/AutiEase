import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isReady = false;

  Future<void> init({
    String language = "en-US",
    double speechRate = 0.4,
    double volume = 1.0,
    double pitch = 1.0,
  }) async {
    try {
      final engines = await _tts.getEngines;
      if (engines == null || (engines as List).isEmpty) {
        debugPrint("No TTS engine available");
        _isReady = false;
        return;
      }

      _tts.setStartHandler(() => debugPrint("TTS Started"));
      _tts.setCompletionHandler(() => debugPrint("TTS Completed"));
      _tts.setErrorHandler((message) => debugPrint("TTS Error: $message"));

      await _tts.setLanguage(language);
      await _tts.setSpeechRate(speechRate);
      await _tts.setVolume(volume);
      await _tts.setPitch(pitch);

      await _tts.awaitSpeakCompletion(true);

      _isReady = true;
      debugPrint("TTS initialized successfully");
    } catch (e) {
      debugPrint("TTS init error: $e");
      _isReady = false;
    }
  }

  Future<void> speak(String text) async {
    if (!_isReady) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint("TTS speak error: $e");
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void dispose() {
    _tts.stop();
  }
}
