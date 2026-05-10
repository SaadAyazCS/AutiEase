import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

/// App-wide speech-to-text using Vosk (Offline & Silent).
/// Now supports manual stopping via the UI.
class SpeechToTextService {
  SpeechToTextService._();
  static final SpeechToTextService instance = SpeechToTextService._();
  factory SpeechToTextService() => instance;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  SpeechService? _speechService;
  
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Compatibility property
  void Function(String status)? statusListener;

  // To allow manual stopping from outside
  Completer<String?>? _currentSessionCompleter;
  String _currentSessionTranscription = "";
  bool _isSessionFinished = false;
  Timer? _sessionTimeoutTimer;
  void Function(String partial)? _onPartialResultCallback;
  StreamSubscription<String>? _resultSubscription;
  StreamSubscription<String>? _partialSubscription;

  /// Initializes the Vosk engine.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      var modelPath = await ModelLoader().loadFromAssets('assets/models/vosk-model.zip');
      
      // Try both possible paths (nested folder or root)
      try {
        _model = await _vosk.createModel('$modelPath/vosk-model');
      } catch (_) {
        _model = await _vosk.createModel(modelPath);
      }
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('Vosk initialization error: $e');
      return false;
    }
  }

  /// Forcefully stop the current session and return what was heard.
  Future<void> stop() async {
    if (_isSessionFinished) return;
    _isSessionFinished = true;
    
    _sessionTimeoutTimer?.cancel();
    _resultSubscription?.cancel();
    _partialSubscription?.cancel();
    _resultSubscription = null;
    _partialSubscription = null;
    
    // Complete immediately so the UI responds instantly
    if (_currentSessionCompleter != null && !_currentSessionCompleter!.isCompleted) {
      _currentSessionCompleter!.complete(_currentSessionTranscription.isEmpty ? null : _currentSessionTranscription);
    }
    
    try {
      if (_speechService != null) {
        await _speechService!.stop();
        // Do NOT nullify _speechService; reuse it for the next listen
      }
    } catch (e) {
      debugPrint('Vosk stop error: $e');
    }
  }

  /// Listens until stop() is called, or the 20-second safety timeout is reached.
  Future<String?> listenOnce({
    Duration timeout = const Duration(seconds: 20), // Long safety timeout
    void Function(String partial)? onPartialResult,
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    // If a session is already running, stop it first
    if (_currentSessionCompleter != null && !_currentSessionCompleter!.isCompleted) {
      await stop();
    }

    _currentSessionCompleter = Completer<String?>();
    _currentSessionTranscription = "";
    _isSessionFinished = false;
    _onPartialResultCallback = onPartialResult;

    // Safety timeout to prevent battery drain
    _sessionTimeoutTimer = Timer(timeout, stop);

    try {
      // Initialize service only once
      if (_speechService == null) {
        final recognizer = await _vosk.createRecognizer(model: _model!, sampleRate: 16000);
        _speechService = await _vosk.initSpeechService(recognizer);
      }

      // Cancel old subscriptions just in case
      await _resultSubscription?.cancel();
      await _partialSubscription?.cancel();

      _resultSubscription = _speechService!.onResult().listen((result) {
        final Map<String, dynamic> data = jsonDecode(result);
        final String text = data['text'] ?? "";
        if (text.isNotEmpty) {
          _currentSessionTranscription = text;
          _onPartialResultCallback?.call(text);
        }
      });

      _partialSubscription = _speechService!.onPartial().listen((partial) {
        final Map<String, dynamic> data = jsonDecode(partial);
        final String text = data['partial'] ?? "";
        if (text.isNotEmpty) {
          _onPartialResultCallback?.call(text);
          _currentSessionTranscription = text;
        }
      });

      await _speechService!.start();
      statusListener?.call('listening');
      
    } catch (e) {
      debugPrint('Vosk listen error: $e');
      await stop();
    }

    return _currentSessionCompleter!.future;
  }
}
