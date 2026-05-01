import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../services/ai_context_service.dart';
import '../ui/glass_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _modelAssetName = 'models/gemma-2b-it-cpu-int4.bin';
  static const String _modelBundlePath = 'assets/$_modelAssetName';

  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final AiContextService _contextService = AiContextService();
  bool _isLoading = false;
  bool _modelLoading = false;
  bool _modelReady = false;

  static const String _systemPrompt = '''
You are HAVEN, an emergency AI assistant for civilians in war zones and conflict areas.
Your role is to provide immediate, life-saving guidance.

CRITICAL RULES:
- Always prioritize safety and survival
- Give clear, step-by-step instructions
- Be concise - users may be in danger
- Use cached local context when it is relevant
- Tell users when local context may be stale
- Support multiple languages - respond in the user's language
- For medical emergencies, provide immediate actionable steps
- For evacuation, ask for current location context
''';

  @override
  void initState() {
    super.initState();
    _addMessage(
      'ai',
      'Local context is ready. I am loading offline AI in the background.',
    );
    _initModel();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_modelReady) {
      FlutterGemmaPlugin.instance.close();
    }
    super.dispose();
  }

  Future<void> _initModel() async {
    if (_modelReady || _modelLoading) return;

    try {
      setState(() => _modelLoading = true);
      final gemma = FlutterGemmaPlugin.instance;

      if (!await gemma.isLoaded) {
        await for (final _ in gemma.loadAssetModelWithProgress(
          fullPath: _modelAssetName,
        )) {}
      }

      await gemma.init(maxTokens: 1024);
      if (!mounted) return;

      setState(() => _modelReady = true);
      _addMessage(
        'ai',
        'HAVEN is ready. I can use cached local manuals, safe places, and news.',
      );
    } catch (_) {
      if (!mounted) return;

      _addMessage(
        'ai',
        'Model loading failed. Please make sure $_modelBundlePath is bundled with the app.',
      );
    } finally {
      if (mounted) setState(() => _modelLoading = false);
    }
  }

  void _addMessage(String role, String content) {
    if (!mounted) return;

    setState(() {
      _messages.add({'role': role, 'content': content});
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!_modelReady) {
      await _initModel();
      if (!_modelReady) return;
    }

    _controller.clear();
    _addMessage('user', text);
    setState(() => _isLoading = true);

    try {
      final localContext = _contextService.buildContext();
      final response = await FlutterGemmaPlugin.instance.getResponse(
        prompt: '$_systemPrompt\n\n$localContext\n\nUser: $text\nHAVEN:',
      );
      _addMessage('ai', response ?? 'No response. Please try again.');
    } catch (_) {
      _addMessage('ai', 'Error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusBanner(modelReady: _modelReady, modelLoading: _modelLoading),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            itemCount: _messages.length + (_isLoading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _messages.length) {
                return const _TypingIndicator();
              }
              final msg = _messages[index];
              return _MessageBubble(
                content: msg['content']!,
                isUser: msg['role'] == 'user',
              );
            },
          ),
        ),
        GlassPanel(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(10),
          borderRadius: 28,
          opacity: 0.2,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Ask HAVEN using cached local context...',
                      hintStyle: TextStyle(
                        color: GlassColors.textTertiary,
                        fontSize: 12,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GlassIconButton(
                onPressed: _sendMessage,
                icon: Icons.arrow_upward_rounded,
                color: GlassColors.textPrimary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.modelReady, required this.modelLoading});

  final bool modelReady;
  final bool modelLoading;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 24,
      opacity: 0.18,
      child: Row(
        children: [
          if (modelLoading)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            GlassPill(
              label: modelReady ? 'AI READY' : 'AI INITIALIZING',
              icon: modelReady ? Icons.memory : Icons.hourglass_empty,
              color: modelReady ? GlassColors.safe : GlassColors.amber,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              modelReady
                  ? 'Uses cached manuals, safe places, and local reports.'
                  : 'Gemma is loading automatically with current app context.',
              style: const TextStyle(
                color: GlassColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.content, required this.isUser});

  final String content;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? GlassColors.emergency.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isUser ? const Radius.circular(2) : null,
            bottomLeft: !isUser ? const Radius.circular(2) : null,
          ),
          border: Border.all(
            color: isUser
                ? GlassColors.emergency.withValues(alpha: 0.36)
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          content,
          style: const TextStyle(
            color: GlassColors.textPrimary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'HAVEN is thinking...',
          style: TextStyle(color: GlassColors.safe, fontSize: 12),
        ),
      ),
    );
  }
}
