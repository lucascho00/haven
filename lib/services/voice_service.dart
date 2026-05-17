import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Lightweight wrapper around `speech_to_text` + `flutter_tts` so the UI
/// doesn't have to know the platform plumbing. All access is via the
/// singleton; both subsystems are lazily initialised on first use.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttInitialised = false;
  bool _ttsInitialised = false;
  String? _lastError;

  bool get isListening => _stt.isListening;
  bool get isAvailable => _sttInitialised;
  String? get lastError => _lastError;

  Future<bool> ensureInitialised() async {
    if (!_sttInitialised) {
      try {
        _sttInitialised = await _stt.initialize(
          onError: (err) {
            _lastError = err.errorMsg;
            debugPrint('STT error: ${err.errorMsg} (permanent=${err.permanent})');
          },
          onStatus: (status) => debugPrint('STT status: $status'),
        );
      } catch (e) {
        _lastError = '$e';
        _sttInitialised = false;
      }
    }
    if (!_ttsInitialised) {
      try {
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(0.5);
        _ttsInitialised = true;
      } catch (e) {
        debugPrint('TTS init failed: $e');
      }
    }
    return _sttInitialised;
  }

  /// Begin a single push-to-talk capture. Final transcript is delivered to
  /// [onFinal] when the user stops speaking (or [stop] is called).
  Future<bool> startListening({
    required void Function(String partial) onPartial,
    required void Function(String finalText) onFinal,
    String? localeId,
  }) async {
    final ok = await ensureInitialised();
    if (!ok) return false;
    try {
      await _stt.listen(
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (SpeechRecognitionResult r) {
          if (r.finalResult) {
            onFinal(r.recognizedWords);
          } else {
            onPartial(r.recognizedWords);
          }
        },
      );
      return true;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_stt.isListening) await _stt.stop();
  }

  /// Best-effort guess at a TTS locale that matches the dominant script in
  /// [text]. Returns null if English is fine.
  String? _ttsLocaleFor(String text) {
    if (RegExp(r'[؀-ۿ]').hasMatch(text)) return 'fa-IR';
    if (RegExp(r'[가-힯]').hasMatch(text)) return 'ko-KR';
    return null; // default — English
  }

  Future<void> speak(String text) async {
    await ensureInitialised();
    if (text.trim().isEmpty) return;
    final locale = _ttsLocaleFor(text);
    try {
      if (locale != null) {
        await _tts.setLanguage(locale);
      } else {
        await _tts.setLanguage('en-US');
      }
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
