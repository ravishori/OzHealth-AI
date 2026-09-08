import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/error/error_reporter.dart';
import 'package:vitapulse_ai/features/splash/splash_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/welcome_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/register_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/login_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/otp_screen.dart';
import 'package:vitapulse_ai/features/onboarding/presentation/onboarding_screen.dart';
import 'package:vitapulse_ai/features/home/presentation/home_screen.dart';
import 'package:vitapulse_ai/features/profile/presentation/profile_screen.dart';
import 'package:vitapulse_ai/features/family/presentation/family_screen.dart';
import 'package:vitapulse_ai/features/family/presentation/add_family_screen.dart';
import 'package:vitapulse_ai/features/family/presentation/edit_family_screen.dart';
import 'package:vitapulse_ai/features/records/presentation/records_screen.dart';
import 'package:vitapulse_ai/features/records/presentation/upload_record_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_scan_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_review_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_detail_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_manual_entry_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_manual_review_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_search_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_detail_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_favourites_screen.dart';
import 'package:vitapulse_ai/features/reminders/presentation/reminders_screen.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';
import 'package:vitapulse_ai/features/health_monitoring/presentation/health_monitoring_screen.dart';
import 'package:vitapulse_ai/features/health_monitoring/presentation/log_metric_screen.dart';
import 'package:vitapulse_ai/features/ai_assistant/presentation/ai_chat_screen.dart';
import 'package:vitapulse_ai/features/ai_assistant/presentation/ai_conversation_history_screen.dart';
import 'package:vitapulse_ai/features/emergency/presentation/emergency_screen.dart';
import 'package:vitapulse_ai/features/nearby/presentation/nearby_screen.dart';
import 'package:vitapulse_ai/features/interactions/presentation/interaction_check_screen.dart';
import 'package:vitapulse_ai/features/symptoms/presentation/symptom_checker_screen.dart';
import 'package:vitapulse_ai/features/lab_analysis/presentation/lab_analysis_screen.dart';
import 'package:vitapulse_ai/features/health_insights/presentation/health_insights_screen.dart';
import 'package:vitapulse_ai/features/eprescriptions/presentation/eprescription_list_screen.dart';
import 'package:vitapulse_ai/features/eprescriptions/presentation/eprescription_scan_screen.dart';
import 'package:vitapulse_ai/features/eprescriptions/presentation/eprescription_result_screen.dart';
import 'package:vitapulse_ai/features/settings/presentation/appearance_screen.dart';
import 'package:vitapulse_ai/features/legal/legal_screens.dart';
import 'package:vitapulse_ai/core/config/app_env.dart';
import 'package:vitapulse_ai/core/router/page_transitions.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',

  // Report navigation errors (bad route params, missing routes, etc.)
  errorBuilder: (context, state) {
    ErrorReporter.report(
      state.error ?? Exception('Navigation error: ${state.uri}'),
      StackTrace.current,
      context: 'navigation:${state.uri}',
    );
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Page not found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  },

  // Update ErrorReporter's screen context on every navigation event
  observers: [_ScreenTrackingObserver()],

  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/splash'),
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/legal/consent', builder: (_, __) => const ConsentScreen()),
    GoRoute(path: '/legal/privacy', builder: (_, __) => const PrivacyPolicyScreen()),
    GoRoute(path: '/legal/terms', builder: (_, __) => const TermsScreen()),
    GoRoute(
      path: '/legal/delete-account',
      builder: (_, __) => const DeleteAccountScreen(),
    ),
    GoRoute(path: '/auth/welcome', builder: (_, __) => const WelcomeScreen()),
    GoRoute(
      path: '/auth/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(path: '/auth/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/auth/otp',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>;
        return OtpScreen(
          identifier: extra['identifier'],
          purpose: extra['purpose'],
          name: extra['name'],
          age: extra['age'] as int?,
          gender: extra['gender'] as String?,
          bloodGroup: extra['blood_group'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeScreen(),
      routes: [
        GoRoute(path: 'profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(path: 'family', builder: (_, __) => const FamilyScreen()),
        GoRoute(path: 'family/add', builder: (_, __) => const AddFamilyMemberScreen()),
        GoRoute(
          path: 'family/edit/:id',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '');
            if (id == null) {
              return const Scaffold(
                body: Center(child: Text('Invalid family member')),
              );
            }
            final extra = state.extra;
            Map<String, dynamic>? initial;
            if (extra is Map) {
              initial = Map<String, dynamic>.from(extra);
            }
            return EditFamilyMemberScreen(
              memberId: id,
              initialMember: initial,
            );
          },
        ),
        GoRoute(path: 'records', builder: (_, __) => const RecordsScreen()),
        GoRoute(path: 'records/upload', builder: (_, __) => const UploadRecordScreen()),
        GoRoute(path: 'prescriptions/scan', builder: (_, __) => const PrescriptionScanScreen()),
        GoRoute(
          path: 'prescriptions/manual',
          builder: (_, __) => const PrescriptionManualEntryScreen(),
        ),
        GoRoute(
          path: 'prescriptions/manual/review',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is! Map) {
              return const Scaffold(
                body: Center(child: Text('Missing manual review data')),
              );
            }
            final map = Map<String, dynamic>.from(extra);
            final rawMeds = map['medicines'];
            final medicines = rawMeds is List
                ? rawMeds
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList()
                : <Map<String, dynamic>>[];
            final fm = map['family_member_id'];
            final familyMemberId = fm is int ? fm : int.tryParse('$fm');
            return PrescriptionManualReviewScreen(
              medicines: medicines,
              doctorName: map['doctor_name']?.toString(),
              familyMemberId: familyMemberId,
            );
          },
        ),
        GoRoute(
          path: 'prescriptions/review',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is! Map) {
              return const Scaffold(
                body: Center(child: Text('Missing OCR review data')),
              );
            }
            final map = Map<String, dynamic>.from(extra);
            return PrescriptionReviewScreen(
              filePath: map['filePath']?.toString() ?? '',
              ocrResult: Map<String, dynamic>.from(map['ocrResult'] as Map? ?? {}),
            );
          },
        ),
        GoRoute(
          path: 'prescriptions/:id',
          builder: (_, state) => PrescriptionDetailScreen(
            prescriptionId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(path: 'medicines', builder: (_, __) => const MedicineSearchScreen()),
        GoRoute(
          path: 'medicines/favourites',
          builder: (_, __) => const MedicineFavouritesScreen(),
        ),
        GoRoute(
          path: 'medicines/:id',
          builder: (_, state) => MedicineDetailScreen(
            medicineId: state.pathParameters['id']!,
            extra: state.extra as Map<String, dynamic>?,
          ),
        ),
        GoRoute(path: 'reminders', builder: (_, __) => const RemindersScreen()),
        GoRoute(path: 'reminders/add', builder: (_, __) => const AddReminderScreen()),
        GoRoute(
          path: 'reminders/edit',
          builder: (_, state) => AddReminderScreen(
            initialReminder: state.extra as Map<String, dynamic>?,
          ),
        ),
        GoRoute(path: 'health', builder: (_, __) => const HealthMonitoringScreen()),
        GoRoute(path: 'health/log', builder: (_, __) => const LogMetricScreen()),
        GoRoute(
          path: 'health/edit',
          builder: (_, state) {
            final extra = state.extra;
            Map<String, dynamic>? metric;
            String? metricType;
            if (extra is Map) {
              final raw = Map<String, dynamic>.from(extra);
              metricType = raw['metric_type']?.toString();
              final nested = raw['metric'];
              if (nested is Map) {
                metric = Map<String, dynamic>.from(nested);
              } else {
                metric = raw;
              }
            }
            return LogMetricScreen(
              initialMetric: metric,
              initialMetricTypeKey: metricType,
            );
          },
        ),
        GoRoute(
          path: 'ai-chat',
          pageBuilder: (context, state) => fadeThroughPage(
            key: state.pageKey,
            child: const AiChatScreen(),
          ),
        ),
        GoRoute(
          path: 'ai-chat/history',
          builder: (_, __) => const AiConversationHistoryScreen(),
        ),
        GoRoute(path: 'emergency', builder: (_, __) => const EmergencyScreen()),
        GoRoute(path: 'nearby', builder: (_, __) => const NearbyScreen()),
        GoRoute(path: 'interactions', builder: (_, __) => const InteractionCheckScreen()),
        GoRoute(path: 'symptoms', builder: (_, __) => const SymptomCheckerScreen()),
        GoRoute(path: 'lab-analysis', builder: (_, __) => const LabAnalysisScreen()),
        GoRoute(
          path: 'insights',
          pageBuilder: (context, state) => fadeThroughPage(
            key: state.pageKey,
            child: const HealthInsightsScreen(),
          ),
        ),
        GoRoute(
          path: 'eprescriptions',
          redirect: (_, __) =>
              AppEnv.showEprescriptions ? null : '/home',
          builder: (_, __) => const EPrescriptionListScreen(),
        ),
        GoRoute(
          path: 'eprescriptions/scan',
          redirect: (_, __) =>
              AppEnv.showEprescriptions ? null : '/home',
          builder: (_, __) => const EPrescriptionScanScreen(),
        ),
        GoRoute(
          path: 'eprescriptions/:id',
          redirect: (_, __) =>
              AppEnv.showEprescriptions ? null : '/home',
          builder: (_, state) => EPrescriptionResultScreen(
            eprescriptionId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(path: 'settings/appearance', builder: (_, __) => const AppearanceScreen()),
      ],
    ),
  ],
);

/// Updates ErrorReporter's current screen context on each navigation.
/// This means all error reports include the screen name the user was on.
class _ScreenTrackingObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _track(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _track(previousRoute);
  }

  void _track(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null) {
      ErrorReporter.setScreen(name);
    }
  }
}
