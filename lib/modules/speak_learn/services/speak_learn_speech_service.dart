import '../../../services/speech_to_text_service.dart';
import '../../../services/tts_service.dart';

/// TTS plus STT for Speak & Learn. STT is delegated to [SpeechToTextService]
/// so other features can use the same recognizer.
class SpeakLearnSpeechService {
  SpeakLearnSpeechService()
      : _tts = TtsService(),
        _stt = SpeechToTextService();

  final TtsService _tts;
  final SpeechToTextService _stt;

  bool _ttsReady = false;

  Future<void> initTts() async {
    await _tts.init(language: 'en-US', speechRate: 0.42, volume: 1.0, pitch: 1.0);
    _ttsReady = true;
  }

  Future<void> dispose() async {
    await _stt.stop();
    _tts.dispose();
  }

  Future<void> speak(String text) async {
    if (!_ttsReady) {
      await initTts();
    }
    await _tts.speak(text);
  }

  Future<bool> ensureSpeechPermission() async {
    return _stt.initialize();
  }

  Future<void> stopListening() async {
    await _stt.stop();
  }

  /// Listens until final result, error, or [timeout].
  /// Uses longer defaults so children who pause between words are not cut off.
  /// [onPartialResult] fires with live words so the UI can update in real-time.
  Future<String?> listenOnce({
    Duration timeout = const Duration(seconds: 20),
    void Function(String partial)? onPartialResult,
  }) {
    return _stt.listenOnce(
      timeout: timeout,
      onPartialResult: onPartialResult,
    );
  }
}
