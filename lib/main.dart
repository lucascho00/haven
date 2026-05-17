import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/core/api/flutter_gemma.dart';

import 'screens/haven_home_screen.dart';
import 'services/background_refresh_service.dart';
import 'services/local_agent_service.dart';
import 'storage/haven_cache.dart';
import 'ui/glass_theme.dart';

const String _dartDefineToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HavenCache.init();
  await BackgroundRefreshService.configure();

  bool envLoaded = false;
  try {
    await dotenv.load(fileName: '.env');
    envLoaded = true;
  } catch (e) {
    debugPrint('HAVEN: dotenv.load(.env) failed — $e');
  }
  final envToken = dotenv.env['HUGGINGFACE_TOKEN']?.trim() ?? '';
  final token = envToken.isNotEmpty
      ? envToken
      : (_dartDefineToken.isNotEmpty ? _dartDefineToken : null);
  debugPrint(
    'HAVEN: dotenv loaded=$envLoaded | HUGGINGFACE_TOKEN '
    '${token == null ? "MISSING" : "present (${token.substring(0, 6)}…, ${token.length} chars)"}',
  );

  FlutterGemma.initialize(huggingFaceToken: token, maxDownloadRetries: 10);
  // Start the Gemma 4 install as early as possible — by the time the user
  // reaches the Agent tab the model is already on its way or ready.
  debugPrint('HAVEN: kicking LocalAgentService.ensureInstalled() at startup');
  unawaited(
    LocalAgentService.instance.ensureInstalled().then(
      (_) => debugPrint(
        'HAVEN: ensureInstalled() future completed — '
        'stage=${LocalAgentService.instance.stage.name}, '
        'error=${LocalAgentService.instance.error ?? "none"}',
      ),
      onError: (Object e) =>
          debugPrint('HAVEN: ensureInstalled() threw — $e'),
    ),
  );
  runApp(const HavenApp());
}

class HavenApp extends StatelessWidget {
  const HavenApp({super.key, this.refreshOnOpen = true});

  final bool refreshOnOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HAVEN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: GlassColors.emergency,
          surface: GlassColors.backgroundTop,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: GlassColors.textPrimary,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.7,
          ),
          titleMedium: TextStyle(
            color: GlassColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          bodyMedium: TextStyle(color: GlassColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: GlassColors.textPrimary),
        useMaterial3: true,
      ),
      home: HavenHomeScreen(refreshOnOpen: refreshOnOpen),
    );
  }
}
