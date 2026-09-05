/// Riverpod ProviderObserver — catches unhandled provider errors.
///
/// When a provider throws during build or update, Riverpod propagates the
/// error up to the widget tree. If it goes uncaught there it becomes a
/// FlutterError (handled by main.dart). This observer gives us an early
/// hook to log and report provider-layer failures before they reach the UI.
///
/// Register it in main.dart:
///   ProviderScope(
///     observers: [AppProviderObserver()],
///     child: VitaPulseApp(),
///   )
library app_provider_observer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/core/utils/debug_logger.dart';

class AppProviderObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    DebugLogger.error(
      'ProviderObserver',
      'Provider ${provider.name ?? provider.runtimeType} failed: $error',
      error,
    );
    ErrorReporter.report(
      error,
      stackTrace,
      context: 'provider:${provider.name ?? provider.runtimeType}',
    );
  }
}
