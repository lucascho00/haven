import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wraps `speech_to_text` + `flutter_tts` and pins the iOS audio session into
/// a playback-friendly state so TTS still plays after STT has used the mic.
/// Singleton; both subsystems are lazily initialised on first use.
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
            debugPrint(
              'Voice/STT error: ${err.errorMsg} (permanent=${err.permanent})',
            );
          },
          onStatus: (status) => debugPrint('Voice/STT status: $status'),
        );
        debugPrint('Voice/STT initialised=$_sttInitialised');
      } catch (e) {
        _lastError = '$e';
        _sttInitialised = false;
        debugPrint('Voice/STT initialise threw: $e');
      }
    }
    if (!_ttsInitialised) {
      try {
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(0.5);
        _tts.setStartHandler(
          () => debugPrint('Voice/TTS start'),
        );
        _tts.setCompletionHandler(
          () => debugPrint('Voice/TTS completion'),
        );
        _tts.setErrorHandler(
          (msg) => debugPrint('Voice/TTS error: $msg'),
        );
        _tts.setCancelHandler(
          () => debugPrint('Voice/TTS cancel'),
        );
        await _configureIosAudio();
        _ttsInitialised = true;
        debugPrint('Voice/TTS initialised');
      } catch (e) {
        debugPrint('Voice/TTS init failed: $e');
      }
    }
    // iOS: prime AVAudioSession so the first real speak() actually produces
    // audible output. Without this, AVSpeechSynthesizer often stays silent
    // until some other audio event (e.g. mic capture) activates the session.
    if (_ttsInitialised && !_ttsPrimed) {
      await _primeIosTts();
    }
    return _sttInitialised;
  }

  bool _ttsPrimed = false;

  Future<void> _primeIosTts() async {
    if (!Platform.isIOS) {
      _ttsPrimed = true;
      return;
    }
    try {
      await _tts.setLanguage('en-US');
      // A single space is short enough to be inaudible but long enough to
      // force AVAudioSession activation. After this, real speak() calls
      // produce sound on the first try.
      await _tts.speak(' ');
      _ttsPrimed = true;
      debugPrint('Voice/TTS audio session primed');
    } catch (e) {
      debugPrint('Voice/TTS prime failed: $e');
    }
  }

  /// Force the iOS AVAudioSession into a category that lets TTS play even
  /// after speech_to_text has flipped it to record mode. Must be re-applied
  /// before every speak() because STT keeps flipping the session back.
  Future<void> _configureIosAudio() async {
    if (!Platform.isIOS) return;
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    } catch (e) {
      debugPrint('Voice/TTS setIosAudioCategory failed: $e');
    }
  }

  /// Begin a single push-to-talk capture. Cancels any prior session first so
  /// a wedged STT state can't block a new listen. Final transcript is
  /// delivered to [onFinal] when the user stops speaking (or [stopListening]
  /// is called). Returns true if listening actually started.
  Future<bool> startListening({
    required void Function(String partial) onPartial,
    required void Function(String finalText) onFinal,
    String? localeId,
  }) async {
    final ok = await ensureInitialised();
    if (!ok) {
      debugPrint('Voice/STT not initialised, cannot start listening');
      return false;
    }
    // Defensive: cancel any in-flight session before starting a new one. On
    // iOS a stuck STT session is the #1 reason the mic "works once then dies".
    if (_stt.isListening) {
      debugPrint('Voice/STT was still listening — cancelling first');
      try {
        await _stt.cancel();
      } catch (e) {
        debugPrint('Voice/STT cancel before listen failed: $e');
      }
    }
    // Stop any in-flight TTS so the mic isn't fighting the speaker.
    try {
      await _tts.stop();
    } catch (_) {}

    _lastError = null;
    try {
      debugPrint(
        'Voice/STT listen(localeId=${localeId ?? "(default)"}, mode=dictation)',
      );
      await _stt.listen(
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (SpeechRecognitionResult r) {
          if (r.finalResult) {
            debugPrint('Voice/STT final: "${r.recognizedWords}"');
            onFinal(r.recognizedWords);
          } else {
            onPartial(r.recognizedWords);
          }
        },
      );
      return true;
    } catch (e) {
      _lastError = '$e';
      debugPrint('Voice/STT listen() threw: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_stt.isListening) {
      debugPrint('Voice/STT stop()');
      try {
        await _stt.stop();
      } catch (e) {
        debugPrint('Voice/STT stop() threw: $e');
      }
    }
  }

  /// Best-effort guess at a TTS locale that matches the dominant script in
  /// [text]. Returns null if English is fine.
  String? _ttsLocaleFor(String text) {
    if (RegExp(r'[؀-ۿ]').hasMatch(text)) return 'fa-IR';
    if (RegExp(r'[가-힯]').hasMatch(text)) return 'ko-KR';
    return null;
  }

  Future<void> speak(String text) async {
    await ensureInitialised();
    if (text.trim().isEmpty) return;

    // Re-apply the iOS audio category every time — STT flips the session into
    // record mode and won't restore it on its own, so TTS would otherwise stay
    // silent after the first mic use.
    await _configureIosAudio();

    final locale = _ttsLocaleFor(text);
    try {
      await _tts.setLanguage(locale ?? 'en-US');
      await _tts.stop();
      debugPrint(
        'Voice/TTS speak(lang=${locale ?? "en-US"}, chars=${text.length})',
      );
      await _tts.speak(text);
    } catch (e) {
      debugPrint('Voice/TTS speak failed: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
