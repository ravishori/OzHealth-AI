import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/core/router/app_router.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: VitaPulseApp())); // UI first
  // Heavy init runs after UI starts (via AppInitializer in SplashScreen)
}

class VitaPulseApp extends StatelessWidget {
  const VitaPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'VitaPulse AI',
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
