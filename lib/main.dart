import 'package:flutter/material.dart';

import 'screens/haven_home_screen.dart';
import 'services/background_refresh_service.dart';
import 'storage/haven_cache.dart';
import 'ui/glass_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HavenCache.init();
  await BackgroundRefreshService.configure();
  runApp(const HavenApp());
}

class HavenApp extends StatelessWidget {
  const HavenApp({super.key});

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
      home: const HavenHomeScreen(),
    );
  }
}
