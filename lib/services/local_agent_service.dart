import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart' show PreferredBackend;
import 'package:path_provider/path_provider.dart';

/// Stages the Gemma 4 weights move through from app launch to ready.
enum AgentInstallStage {
  idle,
  checking,
  downloading,
  installed,
  error,
}

/// User preference for the LiteRT-LM accelerator backend.
enum BackendChoice {
  auto, // Try GPU first, fall back to CPU on failure.
  gpu,  // Force GPU (Metal on iOS, OpenCL on Android). No fallback.
  cpu;  // Force CPU. Slower but works everywhere, including iOS Simulator.

  String get displayName => switch (this) {
    BackendChoice.auto => 'Auto (GPU → CPU)',
    BackendChoice.gpu => 'GPU only',
    BackendChoice.cpu => 'CPU only',
  };

  PreferredBackend get preferredBackend => switch (this) {
    BackendChoice.auto || BackendChoice.gpu => PreferredBackend.gpu,
    BackendChoice.cpu => PreferredBackend.cpu,
  };

  bool get allowsFallback => this == BackendChoice.auto;

  static BackendChoice fromName(String name) {
    return BackendChoice.values.firstWhere(
      (b) => b.name == name,
      orElse: () => BackendChoice.auto,
    );
  }
}

/// Process-wide owner of the Gemma 4 install lifecycle. Kicked once from
/// `main.dart` at app start so the model is already on its way (or already
/// present) by the time the user reaches the Agent tab. The chat screen
/// subscribes to this service for progress/state — it never calls
/// FlutterGemma's installer directly.
class LocalAgentService extends ChangeNotifier {
  LocalAgentService._();
  static final LocalAgentService instance = LocalAgentService._();

  static const String modelFile = 'gemma-4-E2B-it.litertlm';
  static const String modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/$modelFile';

  AgentInstallStage _stage = AgentInstallStage.idle;
  int _progress = 0;
  String? _error;
  Future<void>? _activeInstall;

  AgentInstallStage get stage => _stage;
  int get progress => _progress;
  String? get error => _error;
  bool get isInstalled => _stage == AgentInstallStage.installed;
  bool get isWorking =>
      _stage == AgentInstallStage.checking ||
      _stage == AgentInstallStage.downloading;

  /// Backend selection is now always Auto (GPU first, CPU fallback).
  /// Kept as a getter so call-sites in chat_screen don't need rewriting.
  BackendChoice get backendChoice => BackendChoice.auto;

  /// Idempotent. Concurrent callers reuse the in-flight install future.
  Future<void> ensureInstalled() {
    if (_stage == AgentInstallStage.installed) return Future.value();
    final active = _activeInstall;
    if (active != null) return active;
    final fresh = _install();
    _activeInstall = fresh;
    fresh.whenComplete(() {
      if (identical(_activeInstall, fresh)) _activeInstall = null;
    });
    return fresh;
  }

  Future<void> _install() async {
    _error = null;
    _setStage(AgentInstallStage.checking);

    // 1. Disk-first short-circuit. iOS preserves the app's Documents
    //    directory across same-bundle-ID reinstalls, but flutter_gemma's
    //    in-memory install registry resets on every launch — so isModelInstalled
    //    would return false even when the 1.5 GB .litertlm is still sitting
    //    on disk from the last run. Re-register it via `.fromFile()` instead
    //    of redownloading. This is what makes a reinstall fast.
    final existingPath = await _existingModelPath();
    if (existingPath != null) {
      try {
        debugPrint('LocalAgent: registering cached weights at $existingPath');
        await FlutterGemma.installModel(
          modelType: ModelType.gemma4,
          fileType: ModelFileType.litertlm,
        ).fromFile(existingPath).install();
        debugPrint('LocalAgent: cached weights registered, skipping download');
        _setStage(AgentInstallStage.installed);
        return;
      } catch (e) {
        debugPrint(
          'LocalAgent: registering cached file failed ($e) — '
          'will fall through to a fresh download',
        );
      }
    }

    // 2. Otherwise consult flutter_gemma's registry; if it already considers
    //    the model installed (rare without a cached file but possible), use it.
    bool installed;
    try {
      installed = await FlutterGemma.isModelInstalled(modelFile);
    } catch (e) {
      debugPrint('LocalAgent: isModelInstalled threw — $e');
      _setError('Could not check on-device model: $e');
      return;
    }
    debugPrint('LocalAgent: isModelInstalled returned $installed');
    if (installed) {
      _setStage(AgentInstallStage.installed);
      return;
    }

    // 3. Fresh download as a last resort.
    _progress = 0;
    _setStage(AgentInstallStage.downloading);
    debugPrint('LocalAgent: starting download from $modelUrl');

    try {
      var lastLogged = -10;
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(modelUrl)
          .withProgress((p) {
            _progress = p;
            notifyListeners();
            if (p - lastLogged >= 10 || p == 100) {
              lastLogged = p;
              debugPrint('LocalAgent: download progress $p%');
            }
          })
          .install();
      debugPrint('LocalAgent: install() returned successfully');
      _setStage(AgentInstallStage.installed);
    } catch (e) {
      debugPrint('LocalAgent: install() threw — $e');
      _setError(
        'Download failed: $e\n\n'
        'Tip: set HUGGINGFACE_TOKEN in .env (or pass via --dart-define) and '
        'accept the model license at huggingface.co/litert-community/'
        'gemma-4-E2B-it-litert-lm.',
      );
    }
  }

  /// Returns the absolute path to a cached .litertlm in the app's documents
  /// directory if it exists and looks complete (>500 MB sanity floor —
  /// anything smaller is likely a stale half-download or an HF error page).
  Future<String?> _existingModelPath() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File('${docs.path}/$modelFile');
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size < 500 * 1024 * 1024) {
        debugPrint(
          'LocalAgent: cached file too small ($size bytes), ignoring',
        );
        return null;
      }
      debugPrint(
        'LocalAgent: found cached weights ${file.path} '
        '(${(size / 1024 / 1024).round()} MB)',
      );
      return file.path;
    } catch (e) {
      debugPrint('LocalAgent: failed to inspect existing model: $e');
      return null;
    }
  }

  /// Wipes the on-disk weights and resets state. Next `ensureInstalled()`
  /// will redownload from scratch.
  Future<void> uninstall() async {
    try {
      await FlutterGemma.uninstallModel(modelFile);
    } catch (_) {
      // Best effort — fall through and reset state anyway.
    }
    _progress = 0;
    _error = null;
    _setStage(AgentInstallStage.idle);
  }

  void _setStage(AgentInstallStage stage) {
    _stage = stage;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    _stage = AgentInstallStage.error;
    notifyListeners();
  }
}
