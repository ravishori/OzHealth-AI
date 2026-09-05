import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/core/network/server_discovery.dart';
import 'package:vitapulse_ai/core/notifications/local_reminder_notifications.dart';
import 'package:vitapulse_ai/core/providers/app_provider_observer.dart';
import 'package:vitapulse_ai/core/router/app_router.dart';
import 'package:vitapulse_ai/core/router/navigation_service.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. File logger — must be first so all startup traces are captured
  await DebugLogger.init();
  DebugLogger.log('main', 'App starting — HealthNest');

  // 2. Hive — opened early so the ThemeManager can read persisted settings
  //    before the first frame renders (avoids theme flash on startup).
  await Hive.initFlutter();
  await Hive.openBox('app_preferences');

  // 3. Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    } else {
      DebugLogger.error(
        'FlutterError',
        details.exceptionAsString(),
        details.exception,
      );
    }
    ErrorReporter.report(
      details.exception,
      details.stack ?? StackTrace.current,
      context: 'flutter_framework',
    );
  };

  // 4. Platform-level unhandled errors
  PlatformDispatcher.instance.onError = (error, stack) {
    DebugLogger.error('PlatformDispatcher', error.toString(), error);
    ErrorReporter.report(error, stack, context: 'platform_dispatcher');
    return true;
  };

  // 5. Register router with NavigationService for forced logout
  registerRouter(appRouter);

  // 6. Backend discovery — background; first API call awaits it
  unawaited(ServerDiscovery.resolveBaseUrl());

  // 6b. Local medication notification channel + permission (P0)
  unawaited(LocalReminderNotifications.init());

  // 7. Run app inside a guarded zone
  runZonedGuarded(
    () => runApp(
      ProviderScope(
        observers: [AppProviderObserver()],
        child: const VitaPulseApp(),
      ),
    ),
    (error, stack) {
      DebugLogger.error('ZoneError', error.toString(), error);
      ErrorReporter.report(error, stack, context: 'zone_error');
    },
  );
}

/// Allows fire-and-forget futures without a lint warning.
void unawaited(Future<void> future) {
  future.ignore();
}

class VitaPulseApp extends ConsumerWidget {
  const VitaPulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeManagerProvider);

    return MaterialApp.router(
      title:      'HealthNest',
      theme:      AppThemeBuilder.light(settings),
      darkTheme:  AppThemeBuilder.dark(settings),
      themeMode:  settings.themeMode,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,

      // Apply global UX overrides driven by appearance settings
      builder: (context, child) {
        final disableAnim = settings.animationSpeed == AppAnimationSpeed.off;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnim,
          ),
          child: child!,
        );
      },
    );
  }
}
