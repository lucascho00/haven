import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/core/model_response.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/pigeon.g.dart' show PreferredBackend;

import '../models/safe_place.dart';
import '../services/ai_context_service.dart';
import '../services/ai_tools_service.dart';
import '../services/local_agent_service.dart';
import '../services/navigation_service.dart';
import '../services/voice_service.dart';
import '../ui/glass_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _ModelStage { checking, needsDownload, downloading, ready, error, incompatibleHost }

class _ChatScreenState extends State<ChatScreen> {
  static const String _systemPrompt = '''
You are HAVEN, an emergency AI assistant for civilians in war zones and conflict areas.
Your role is to provide immediate, life-saving guidance.

CRITICAL RULES:
- Always prioritize safety and survival.
- Give clear, short, step-by-step instructions. Users may be panicked or hurt.
- ALWAYS respond in the user's input language. If they write in Persian (فارسی),
  reply in Persian. If they write in Arabic (العربية), reply in Arabic. If they
  write in Korean (한국어), reply in Korean. Default to English only when the
  user writes in English.
- Use the cached local context (location, headlines, safe places, manual list)
  when it is relevant. When you need detail you do not have, call the available
  tools (get_safe_places, get_news_article, get_manual_steps).
- Tell users when local context may be stale.
- For medical emergencies, provide immediate actionable steps before any caveats.
- For evacuation questions, name nearby cached safe places from the context.
''';

  final TextEditingController _controller = TextEditingController();
  final List<_ChatMessage> _messages = [];
  final AiContextService _contextService = AiContextService();
  final AiToolsService _toolsService = AiToolsService();

  _ModelStage _stage = _ModelStage.checking;
  int _downloadProgress = 0;
  String? _stageError;

  InferenceModel? _model;
  InferenceChat? _chat;
  bool _generating = false;
  bool _cpuFallbackAttempted = false;
  String? _gpuErrorMessage;

  // Voice (push-to-talk; TTS readback always on — users mute via volume).
  bool _listening = false;

  bool _sessionStartScheduled = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    LocalAgentService.instance.addListener(_onAgentChange);
    // Initial sync — captures state if main.dart's kickoff already finished.
    _onAgentChange();
    // Idempotent: returns the in-flight future if main.dart already started one.
    unawaited(LocalAgentService.instance.ensureInstalled());
  }

  @override
  void dispose() {
    LocalAgentService.instance.removeListener(_onAgentChange);
    _controller.dispose();
    _scrollController.dispose();
    _chat?.close();
    _model?.close();
    super.dispose();
  }

  void _onAgentChange() {
    if (!mounted) return;
    final agent = LocalAgentService.instance;
    switch (agent.stage) {
      case AgentInstallStage.idle:
      case AgentInstallStage.checking:
        setState(() {
          _stage = _ModelStage.checking;
          _stageError = null;
        });
      case AgentInstallStage.downloading:
        setState(() {
          _stage = _ModelStage.downloading;
          _downloadProgress = agent.progress;
          _stageError = null;
        });
      case AgentInstallStage.installed:
        if (_chat != null || _sessionStartScheduled) return;
        _sessionStartScheduled = true;
        unawaited(_runSessionStart());
      case AgentInstallStage.error:
        setState(() {
          _stage = _ModelStage.needsDownload;
          _stageError = agent.error;
        });
    }
  }

  Future<void> _runSessionStart() async {
    try {
      await _prepareSession();
    } catch (e) {
      await _handleSessionFailure(e);
    } finally {
      _sessionStartScheduled = false;
    }
  }

  Future<void> _retryInstall() async {
    if (!mounted) return;
    setState(() {
      _stageError = null;
      _downloadProgress = 0;
    });
    await LocalAgentService.instance.ensureInstalled();
  }

  Future<void> _reinstallModel() async {
    // Tear down any open chat/model so the LiteRT-LM file handle is released
    // before we wipe it on disk.
    final chat = _chat;
    final model = _model;
    _chat = null;
    _model = null;
    _sessionStartScheduled = false;
    try {
      await chat?.close();
    } catch (_) {}
    try {
      await model?.close();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _stageError = null;
      _downloadProgress = 0;
      _cpuFallbackAttempted = false;
      _gpuErrorMessage = null;
    });
    await LocalAgentService.instance.uninstall();
    await LocalAgentService.instance.ensureInstalled();
  }

  Future<void> _handleSessionFailure(Object error) async {
    if (_looksLikeFileCorruption(error)) {
      // Wipe the bad weights and kick a fresh download via the service.
      await LocalAgentService.instance.uninstall();
      if (!mounted) return;
      setState(() {
        _stageError =
            'On-device model file was invalid and has been removed. '
            'Restarting download.\n\nUnderlying error: $error';
      });
      unawaited(LocalAgentService.instance.ensureInstalled());
      return;
    }

    if (!mounted) return;
    if (_cpuFallbackAttempted) {
      // GPU + CPU both failed. On iOS Simulator the usual culprit is the
      // Metal binding-31 limit; on a real device it's more often OOM, a
      // Metal driver bug, or a corrupted cache. Show both errors and let
      // the user pick a forced backend from Settings.
      setState(() {
        _stage = _ModelStage.incompatibleHost;
        _stageError =
            'Both GPU and CPU init failed for the on-device Gemma 4 model.\n\n'
            'GPU error:\n${_gpuErrorMessage ?? "(not captured)"}\n\n'
            'CPU error:\n$error\n\n'
            'Things to try:\n'
            '• Open Settings → Local Agent Backend and force GPU or CPU '
            'explicitly, then tap reset on the Agent tab.\n'
            '• Free up RAM by closing other apps and restart HAVEN.\n'
            '• If both still fail, the .litertlm file may be corrupt — '
            'tap "Reinstall model" below to wipe and redownload.';
      });
      return;
    }
    setState(() {
      _stage = _ModelStage.error;
      _stageError = 'Could not initialize the local model.\n\n$error';
    });
  }

  Future<void> _prepareSession() async {
    _cpuFallbackAttempted = false;
    _gpuErrorMessage = null;
    final choice = LocalAgentService.instance.backendChoice;
    try {
      await _initWithBackend(choice.preferredBackend);
      return;
    } catch (eGpu) {
      if (_looksLikeFileCorruption(eGpu)) rethrow;
      if (!choice.allowsFallback || choice.preferredBackend == PreferredBackend.cpu) {
        rethrow;
      }
      debugPrint('Gemma 4 GPU init failed; falling back to CPU. ($eGpu)');
      _gpuErrorMessage = eGpu.toString();
      _cpuFallbackAttempted = true;
    }
    await _initWithBackend(PreferredBackend.cpu);
  }

  bool _looksLikeFileCorruption(Object error) {
    final s = error.toString();
    return s.contains('memory_mapped_file') ||
        s.contains('Length and offset') ||
        s.contains('file_size');
  }

  Future<void> _initWithBackend(PreferredBackend backend) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: 4096,
      preferredBackend: backend,
    );
    // Static local context lives in the system instruction — sent once, kept
    // in the KV cache, never re-transmitted per turn.
    final systemContext = _contextService.buildSystemContext();
    final chat = await model.createChat(
      systemInstruction: '$_systemPrompt\n\n$systemContext',
      modelType: ModelType.gemma4,
      tools: _toolsService.tools,
      supportsFunctionCalls: true,
      temperature: 0.6,
      topK: 40,
      topP: 0.95,
    );

    if (!mounted) {
      await chat.close();
      await model.close();
      return;
    }

    final cpuNote = backend == PreferredBackend.cpu
        ? ' (CPU backend — responses will be much slower than on a real iPhone)'
        : '';
    setState(() {
      _model = model;
      _chat = chat;
      _stage = _ModelStage.ready;
      _messages
        ..clear()
        ..add(
          _ChatMessage.ai(
            'HAVEN is ready$cpuNote. Generating a situation snapshot from the cached context…',
            streaming: true,
          ),
        );
    });

    // Fire a synthetic first turn so the user sees a useful, grounded snapshot
    // the moment the Agent tab opens — no typing required. We seed the message
    // list with a streaming placeholder above and stream into it below.
    unawaited(_runSituationRead());
  }

  Future<void> _runSituationRead() async {
    final chat = _chat;
    if (chat == null) return;
    final placeholder = _messages.last;
    placeholder.content = '';
    if (mounted) setState(() {});

    const situationPrompt =
        'Briefly read the cached local context and produce a 3-bullet '
        'situation snapshot for the user:\n'
        '1. **Top risks today** — scan the headlines for things like '
        'airstrike, evacuation, ceasefire, blockade, attack.\n'
        '2. **Nearest cached safe places** — name 2-3 of them with type.\n'
        '3. **Most relevant survival manual** — pick one title from the list.\n'
        'Keep each bullet under 25 words. No preamble.';

    int tokenCount = 0;
    final stopwatch = Stopwatch();
    try {
      await chat.addQueryChunk(
        Message.text(text: situationPrompt, isUser: true),
      );
      await for (final response in chat.generateChatResponseAsync()) {
        if (!mounted) break;
        if (response is TextResponse) {
          if (!stopwatch.isRunning) stopwatch.start();
          tokenCount++;
          setState(() => placeholder.content += response.token);
          _scrollToBottomSoon();
        }
      }
    } catch (e) {
      debugPrint('Situation read failed: $e');
      if (placeholder.content.isEmpty) {
        placeholder.content =
            'Ready. Ask me anything — about safe places, recent news, or survival steps.';
      }
    } finally {
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds / 1000.0;
      if (mounted) {
        setState(() {
          placeholder.streaming = false;
          if (tokenCount > 0 && elapsed > 0) {
            placeholder.metric =
                '${(tokenCount / elapsed).toStringAsFixed(1)} tok/s · ${_backendLabel()}';
          }
        });
      }
    }
  }

  Future<void> _resetChat() async {
    _generating = false;
    final chat = _chat;
    final model = _model;
    _chat = null;
    _model = null;
    try {
      await chat?.close();
    } catch (_) {}
    try {
      await model?.close();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _stage = _ModelStage.checking;
    });
    try {
      await _prepareSession();
    } catch (e) {
      await _handleSessionFailure(e);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final chat = _chat;
    if (text.isEmpty || chat == null || _generating) return;

    _controller.clear();
    final aiMessage = _ChatMessage.ai('', streaming: true);
    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messages.add(aiMessage);
      _generating = true;
    });
    _scrollToBottomSoon();

    // LiteRT-LM inference perf measurement. Start clock at first token so we
    // exclude prefill (which dominates on long prompts but is one-time).
    int tokenCount = 0;
    final stopwatch = Stopwatch();

    try {
      await chat.addQueryChunk(Message.text(text: text, isUser: true));

      // Tool-call loop: model can emit text + function calls; after we execute
      // a tool we resume generation so the model can use the result. Capped to
      // prevent runaway loops.
      for (var iteration = 0; iteration < 4; iteration++) {
        if (!mounted) break;
        final pendingCalls = <FunctionCallResponse>[];

        await for (final response in chat.generateChatResponseAsync()) {
          if (!mounted) break;
          if (response is TextResponse) {
            if (!stopwatch.isRunning) stopwatch.start();
            tokenCount++;
            setState(() => aiMessage.content += response.token);
            _scrollToBottomSoon();
          } else if (response is FunctionCallResponse) {
            pendingCalls.add(response);
          } else if (response is ParallelFunctionCallResponse) {
            pendingCalls.addAll(response.calls);
          }
        }

        if (pendingCalls.isEmpty) break;

        // Surface tool use in the message so the user sees what the model is doing.
        final toolNames = pendingCalls.map((c) => c.name).join(', ');
        setState(() {
          aiMessage.content += aiMessage.content.isEmpty
              ? '_Looking up: $toolNames…_\n\n'
              : '\n\n_Looking up: $toolNames…_\n\n';
        });

        for (final call in pendingCalls) {
          debugPrint('Gemma tool call: ${call.name}(${call.args})');
          final result = _toolsService.execute(call.name, call.args);
          await chat.addQueryChunk(
            _toolsService.toolResponse(call.name, result),
          );
          _emitActionFor(call.name, call.args, result);
        }
      }
    } catch (e, st) {
      debugPrint('Gemma generation error: $e\n$st');
      if (mounted) {
        setState(() {
          if (aiMessage.content.isEmpty) {
            aiMessage.content =
                'Could not generate a response. Tap reset (top right) to start a fresh chat — the session context may have grown too large.';
          }
        });
      }
    } finally {
      stopwatch.stop();
      final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
      String? metric;
      if (tokenCount > 0 && elapsedSec > 0) {
        final tps = (tokenCount / elapsedSec).toStringAsFixed(1);
        final backendLabel = _backendLabel();
        metric = '$tps tok/s · $backendLabel';
      }
      if (mounted) {
        setState(() {
          if (aiMessage.content.isEmpty) {
            aiMessage.content =
                'No response was generated. Try rephrasing your question.';
          }
          aiMessage.streaming = false;
          aiMessage.metric = metric;
          _generating = false;
        });
        _maybeSpeakReply(aiMessage);
      }
    }
  }

  /// Translate a tool invocation into a tappable action card appended to the
  /// chat. Only emits for tools that map to a specific in-app destination.
  void _emitActionFor(
    String toolName,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) {
    if (!mounted) return;
    _ChatMessage? card;

    PlaceCategory? parseCategory(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      return PlaceCategory.values
          .where((c) => c.name == raw)
          .cast<PlaceCategory?>()
          .firstWhere((_) => true, orElse: () => null);
    }

    switch (toolName) {
      case 'get_safe_places':
        final cat = parseCategory((args['category'] as String?)?.toLowerCase());
        final count = (result['count'] as int?) ?? 0;
        if (cat != null && count > 0) {
          card = _ChatMessage.action(
            kind: _ActionKind.mapCategory,
            label: 'View $count ${cat.displayName.toLowerCase()} on map',
            subtitle: 'Map tab will filter to ${cat.displayName} only.',
            category: cat,
          );
        }
      case 'find_nearest':
        final cat = parseCategory((args['category'] as String?)?.toLowerCase());
        final found = result['found'] == true;
        if (cat != null && found) {
          final name = result['name'] as String? ?? cat.displayName;
          card = _ChatMessage.action(
            kind: _ActionKind.mapPlace,
            label: 'Show $name on map',
            subtitle: 'Centers the map on the nearest ${cat.displayName}.',
            category: cat,
          );
        }
      case 'get_manual_steps':
        final found = result['found'] == true;
        if (found) {
          final id = result['id'] as String? ?? '';
          final title = result['title'] as String? ?? 'manual';
          card = _ChatMessage.action(
            kind: _ActionKind.settingsManual,
            label: 'Open "$title" in Settings',
            subtitle: 'Full numbered steps are in the Settings tab.',
            placeId: id,
          );
        }
      default:
        return;
    }
    if (card != null) {
      setState(() => _messages.add(card!));
    }
  }

  void _handleActionTap(_ChatMessage card) {
    switch (card.actionKind) {
      case _ActionKind.mapCategory:
        NavigationService.instance.goToMap(category: card.actionCategory);
      case _ActionKind.mapPlace:
        NavigationService.instance.goToMap(category: card.actionCategory);
      case _ActionKind.settingsManual:
        NavigationService.instance.goToSettings();
      case null:
        return;
    }
  }

  Future<void> _startListening() async {
    // Skip only when actually busy generating. Don't gate on our local
    // _listening flag — the VoiceService internally cancels any prior STT
    // session before starting a new one, so a stuck _listening can't keep
    // the mic dead after one use.
    if (_generating) return;
    debugPrint('Chat: mic pressed (was _listening=$_listening)');
    final ok = await VoiceService.instance.startListening(
      onPartial: (text) {
        if (!mounted) return;
        setState(() => _controller.text = text);
      },
      onFinal: (text) {
        if (!mounted) return;
        debugPrint('Chat: STT final received: "$text"');
        setState(() {
          _controller.text = text;
          _listening = false;
        });
        if (text.trim().isNotEmpty) {
          unawaited(_sendMessage());
        }
      },
    );
    if (!mounted) return;
    if (!ok) {
      debugPrint('Chat: VoiceService.startListening returned false');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Microphone unavailable: ${VoiceService.instance.lastError ?? 'permission denied'}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
  }

  Future<void> _stopListening() async {
    debugPrint('Chat: mic released');
    await VoiceService.instance.stopListening();
    if (mounted) setState(() => _listening = false);
  }

  void _maybeSpeakReply(_ChatMessage message) {
    final text = message.content.trim();
    if (text.isEmpty) return;
    unawaited(VoiceService.instance.speak(text));
  }

  void _scrollToBottomSoon() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _backendLabel() {
    final choice = LocalAgentService.instance.backendChoice;
    final attemptedFallback = _cpuFallbackAttempted;
    switch (choice) {
      case BackendChoice.auto:
        return attemptedFallback ? 'CPU (LiteRT)' : 'GPU(Metal) via LiteRT-LM';
      case BackendChoice.gpu:
        return 'GPU(Metal) via LiteRT-LM';
      case BackendChoice.cpu:
        return 'CPU via LiteRT-LM';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusBanner(
          stage: _stage,
          progress: _downloadProgress,
          onReset: _stage == _ModelStage.ready ? _resetChat : null,
        ),
        Expanded(
          child: _stage == _ModelStage.ready
              ? _MessageList(
                  messages: _messages,
                  onActionTap: _handleActionTap,
                  scrollController: _scrollController,
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    if (_stage == _ModelStage.needsDownload ||
                        _stage == _ModelStage.error)
                      _DownloadPrompt(
                        onPressed: _retryInstall,
                        isRetry: _stage == _ModelStage.error,
                        detailedError: _stageError,
                      ),
                    if (_stage == _ModelStage.incompatibleHost)
                      _IncompatibleHostPanel(
                        detailedError: _stageError,
                        onReinstall: _reinstallModel,
                      ),
                    if (_stage == _ModelStage.checking ||
                        _stage == _ModelStage.downloading ||
                        _stage == _ModelStage.incompatibleHost)
                      _PreReadyPlaceholder(stage: _stage),
                  ],
                ),
        ),
        if (_stage == _ModelStage.ready)
          Padding(
            // Float the composer above the keyboard while leaving the floating
            // tab bar at the real bottom of the screen (hidden by the keyboard).
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _Composer(
              controller: _controller,
              enabled: !_generating,
              listening: _listening,
              onSend: _sendMessage,
              onMicPressed: _startListening,
              onMicReleased: _stopListening,
            ),
          ),
      ],
    );
  }
}

enum _ActionKind { mapCategory, mapPlace, settingsManual }

class _ChatMessage {
  _ChatMessage._(this.role, this.content, {this.streaming = false});
  factory _ChatMessage.user(String content) => _ChatMessage._('user', content);
  factory _ChatMessage.ai(String content, {bool streaming = false}) =>
      _ChatMessage._('ai', content, streaming: streaming);

  factory _ChatMessage.action({
    required _ActionKind kind,
    required String label,
    required String subtitle,
    PlaceCategory? category,
    String? placeId,
  }) {
    return _ChatMessage._('action', label)
      ..actionKind = kind
      ..actionSubtitle = subtitle
      ..actionCategory = category
      ..actionPlaceId = placeId;
  }

  final String role;
  String content;
  bool streaming;
  // LiteRT-LM inference perf, e.g. "12.4 tok/s · GPU(Metal)".
  String? metric;

  // Action message fields.
  _ActionKind? actionKind;
  String? actionSubtitle;
  PlaceCategory? actionCategory;
  String? actionPlaceId;

  bool get isUser => role == 'user';
  bool get isAction => role == 'action';
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.stage,
    required this.progress,
    this.onReset,
  });

  final _ModelStage stage;
  final int progress;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon, message) = _statusFor(stage, progress);

    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 24,
      opacity: 0.18,
      child: Row(
        children: [
          if (stage == _ModelStage.checking || stage == _ModelStage.downloading)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: stage == _ModelStage.downloading && progress > 0
                    ? progress / 100
                    : null,
              ),
            )
          else
            GlassPill(label: label, icon: icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: GlassColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (onReset != null) ...[
            const SizedBox(width: 6),
            GlassIconButton(
              icon: Icons.restart_alt,
              color: GlassColors.textPrimary,
              onPressed: onReset,
            ),
          ],
        ],
      ),
    );
  }

  (String, Color, IconData, String) _statusFor(
    _ModelStage stage,
    int progress,
  ) {
    switch (stage) {
      case _ModelStage.checking:
        return (
          'CHECKING',
          GlassColors.amber,
          Icons.hourglass_empty,
          'Looking for the on-device Gemma 4 weights...',
        );
      case _ModelStage.needsDownload:
        return (
          'DOWNLOAD REQUIRED',
          GlassColors.amber,
          Icons.cloud_download_outlined,
          'Gemma 4 E2B (~1.5 GB) is needed once. After this, HAVEN works fully offline.',
        );
      case _ModelStage.downloading:
        return (
          'DOWNLOADING',
          GlassColors.cyan,
          Icons.cloud_download,
          'Downloading Gemma 4 E2B... $progress%',
        );
      case _ModelStage.ready:
        return (
          'AI READY',
          GlassColors.safe,
          Icons.memory,
          'Gemma 4 E2B is running on-device. Uses cached manuals, safe places, and reports.',
        );
      case _ModelStage.error:
        return (
          'ERROR',
          GlassColors.emergency,
          Icons.error_outline,
          'Something went wrong preparing the local model.',
        );
      case _ModelStage.incompatibleHost:
        return (
          'SIMULATOR LIMIT',
          GlassColors.amber,
          Icons.phone_iphone,
          'Gemma 4 needs a physical iPhone. Model is cached and ready.',
        );
    }
  }
}

class _DownloadPrompt extends StatelessWidget {
  const _DownloadPrompt({
    required this.onPressed,
    required this.isRetry,
    this.detailedError,
  });

  final VoidCallback onPressed;
  final bool isRetry;
  final String? detailedError;

  @override
  Widget build(BuildContext context) {
    final hasError = detailedError != null && detailedError!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        borderRadius: 22,
        opacity: 0.15,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRetry ? 'Retry download' : 'One-time setup',
              style: const TextStyle(
                color: GlassColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap to download Gemma 4 E2B (LiteRT-LM). Recommended: WiFi. '
              'After install, the model runs entirely on-device.\n\n'
              'Gemma is a gated model: build with '
              '--dart-define=HUGGINGFACE_TOKEN=hf_... and accept the license '
              'on the HuggingFace model page first.',
              style: TextStyle(color: GlassColors.textSecondary, fontSize: 13),
            ),
            if (hasError) ...[
              const SizedBox(height: 14),
              _ErrorDetails(message: detailedError!),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onPressed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: GlassColors.emergency.withValues(alpha: 0.85),
                  ),
                  child: Text(
                    isRetry ? 'Retry' : 'Download Gemma 4 E2B',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncompatibleHostPanel extends StatelessWidget {
  const _IncompatibleHostPanel({
    required this.detailedError,
    required this.onReinstall,
  });

  final String? detailedError;
  final VoidCallback onReinstall;

  @override
  Widget build(BuildContext context) {
    final hasError =
        detailedError != null && detailedError!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        borderRadius: 22,
        opacity: 0.15,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Could not start the on-device model',
              style: TextStyle(
                color: GlassColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Both GPU and CPU init failed for the cached Gemma 4 weights. '
              'Try forcing one backend explicitly in Settings → Local Agent '
              'Backend and tap reset on this tab. If both still fail the '
              'cached .litertlm file may be corrupt — reinstall it below.',
              style: TextStyle(color: GlassColors.textSecondary, fontSize: 13),
            ),
            if (hasError) ...[
              const SizedBox(height: 14),
              _ErrorDetails(message: detailedError!),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onReinstall,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: GlassColors.emergency.withValues(alpha: 0.85),
                  ),
                  child: const Text(
                    'Reinstall model',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorDetails extends StatelessWidget {
  const _ErrorDetails({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GlassColors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Last error',
            style: TextStyle(
              color: GlassColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Text(
                message,
                style: const TextStyle(
                  color: GlassColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreReadyPlaceholder extends StatelessWidget {
  const _PreReadyPlaceholder({required this.stage});

  final _ModelStage stage;

  @override
  Widget build(BuildContext context) {
    final message = switch (stage) {
      _ModelStage.checking => 'Looking for the local model...',
      _ModelStage.needsDownload =>
        'Once the model is installed, this chat will work fully offline. '
            'You can still browse cached Manuals and the Newspaper now.',
      _ModelStage.downloading =>
        'Hang tight. The model only downloads once. '
            'You can switch tabs while this finishes.',
      _ModelStage.error =>
        'Could not load Gemma 4 E2B. Cached manuals, safe places, and news remain available.',
      _ModelStage.incompatibleHost =>
        'Gemma 4 weights are downloaded and ready, but this host cannot run '
            'the GPU kernels. Quit and re-run on a physical iPhone:\n\n'
            'flutter run -d <iphone-udid> --dart-define=HUGGINGFACE_TOKEN=hf_...',
      _ModelStage.ready => '',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: GlassColors.textSecondary,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.onActionTap,
    required this.scrollController,
  });

  final List<_ChatMessage> messages;
  final ValueChanged<_ChatMessage> onActionTap;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        if (msg.isAction) {
          return _ActionCard(message: msg, onTap: () => onActionTap(msg));
        }
        return _MessageBubble(message: msg);
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.message, required this.onTap});

  final _ChatMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = message.actionCategory?.color ?? GlassColors.cyan;
    final icon = switch (message.actionKind) {
      _ActionKind.mapCategory ||
      _ActionKind.mapPlace =>
        Icons.map_outlined,
      _ActionKind.settingsManual => Icons.menu_book_outlined,
      null => Icons.touch_app_outlined,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassPanel(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(12),
          borderRadius: 18,
          opacity: 0.18,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.85),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: GlassColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((message.actionSubtitle ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message.actionSubtitle!,
                        style: const TextStyle(
                          color: GlassColors.textSecondary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: GlassColors.textTertiary,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final showCursor = message.streaming && message.content.isEmpty;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: message.isUser
              ? GlassColors.emergency.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: message.isUser ? const Radius.circular(2) : null,
            bottomLeft: !message.isUser ? const Radius.circular(2) : null,
          ),
          border: Border.all(
            color: message.isUser
                ? GlassColors.emergency.withValues(alpha: 0.36)
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: showCursor
            ? const Text(
                'HAVEN is thinking...',
                style: TextStyle(color: GlassColors.safe, fontSize: 12),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.content,
                    style: const TextStyle(
                      color: GlassColors.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  if (!message.isUser && message.metric != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt_outlined,
                          size: 12,
                          color: GlassColors.safe.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          message.metric!,
                          style: TextStyle(
                            color: GlassColors.safe.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.listening,
    required this.onSend,
    required this.onMicPressed,
    required this.onMicReleased,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool listening;
  final VoidCallback onSend;
  final VoidCallback onMicPressed;
  final VoidCallback onMicReleased;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      borderRadius: 28,
      opacity: 0.22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Text input + send.
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: TextField(
                    controller: controller,
                    enabled: enabled,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Ask HAVEN…',
                      hintStyle: TextStyle(
                        color: GlassColors.textTertiary,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => enabled ? onSend() : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                onPressed: enabled ? onSend : null,
                icon: Icons.arrow_upward_rounded,
                color: GlassColors.textPrimary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Big push-to-talk pill: makes the "hold" affordance obvious.
          _PushToTalkButton(
            enabled: enabled,
            listening: listening,
            onPressed: onMicPressed,
            onReleased: onMicReleased,
          ),
        ],
      ),
    );
  }
}

class _PushToTalkButton extends StatelessWidget {
  const _PushToTalkButton({
    required this.enabled,
    required this.listening,
    required this.onPressed,
    required this.onReleased,
  });

  final bool enabled;
  final bool listening;
  final VoidCallback onPressed;
  final VoidCallback onReleased;

  @override
  Widget build(BuildContext context) {
    final activeColor = GlassColors.emergency;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => onPressed() : null,
      onTapUp: (_) => onReleased(),
      onTapCancel: onReleased,
      onLongPressStart: enabled ? (_) => onPressed() : null,
      onLongPressEnd: (_) => onReleased(),
      onLongPressCancel: onReleased,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: listening
              ? activeColor.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.10),
          border: Border.all(
            color: listening
                ? Colors.white.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.22),
            width: listening ? 2 : 1,
          ),
          boxShadow: listening
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              listening ? Icons.mic : Icons.mic_none_outlined,
              color: listening ? Colors.white : GlassColors.textPrimary,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              listening
                  ? 'LISTENING — RELEASE TO SEND'
                  : 'HOLD TO TALK',
              style: TextStyle(
                color: listening ? Colors.white : GlassColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
