/// Lightweight navigation service — lets non-widget code (e.g. ApiClient)
/// trigger navigation without importing the full GoRouter / screen graph
/// (which would create circular imports).
///
/// Usage:
///   1. Call [registerRouter] once at startup (before [runApp]).
///   2. From anywhere (including Dio interceptors): call [goToLogin].
library navigation_service;

import 'package:go_router/go_router.dart';

GoRouter? _router;

/// Register the app's GoRouter instance.  Call once in main() before runApp().
void registerRouter(GoRouter router) => _router = router;

/// Navigate to the welcome/login screen, replacing the entire route stack.
/// Safe to call from Dio interceptors or any non-widget context.
void goToLogin() => _router?.go('/auth/welcome');
