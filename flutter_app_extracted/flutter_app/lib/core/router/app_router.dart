import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/features/splash/splash_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/welcome_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/register_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/login_screen.dart';
import 'package:vitapulse_ai/features/auth/presentation/screens/otp_screen.dart';
import 'package:vitapulse_ai/features/home/presentation/home_screen.dart';
import 'package:vitapulse_ai/features/profile/presentation/profile_screen.dart';
import 'package:vitapulse_ai/features/family/presentation/family_screen.dart';
import 'package:vitapulse_ai/features/family/presentation/add_family_screen.dart';
import 'package:vitapulse_ai/features/records/presentation/records_screen.dart';
import 'package:vitapulse_ai/features/records/presentation/upload_record_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_scan_screen.dart';
import 'package:vitapulse_ai/features/prescriptions/presentation/prescription_detail_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_search_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_detail_screen.dart';
import 'package:vitapulse_ai/features/reminders/presentation/reminders_screen.dart';
import 'package:vitapulse_ai/features/reminders/presentation/add_reminder_screen.dart';
import 'package:vitapulse_ai/features/health_monitoring/presentation/health_monitoring_screen.dart';
import 'package:vitapulse_ai/features/health_monitoring/presentation/log_metric_screen.dart';
import 'package:vitapulse_ai/features/ai_assistant/presentation/ai_chat_screen.dart';
import 'package:vitapulse_ai/features/emergency/presentation/emergency_screen.dart';
import 'package:vitapulse_ai/features/nearby/presentation/nearby_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/splash'),
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/auth/welcome', builder: (_, __) => const WelcomeScreen()),
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
        GoRoute(path: 'records', builder: (_, __) => const RecordsScreen()),
        GoRoute(path: 'records/upload', builder: (_, __) => const UploadRecordScreen()),
        GoRoute(path: 'prescriptions/scan', builder: (_, __) => const PrescriptionScanScreen()),
        GoRoute(
          path: 'prescriptions/:id',
          builder: (_, state) => PrescriptionDetailScreen(
            prescriptionId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(path: 'medicines', builder: (_, __) => const MedicineSearchScreen()),
        GoRoute(
          path: 'medicines/:id',
          builder: (_, state) => MedicineDetailScreen(
            medicineId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(path: 'reminders', builder: (_, __) => const RemindersScreen()),
        GoRoute(path: 'reminders/add', builder: (_, __) => const AddReminderScreen()),
        GoRoute(path: 'health', builder: (_, __) => const HealthMonitoringScreen()),
        GoRoute(path: 'health/log', builder: (_, __) => const LogMetricScreen()),
        GoRoute(path: 'ai-chat', builder: (_, __) => const AiChatScreen()),
        GoRoute(path: 'emergency', builder: (_, __) => const EmergencyScreen()),
        GoRoute(path: 'nearby', builder: (_, __) => const NearbyScreen()),
      ],
    ),
  ],
);
