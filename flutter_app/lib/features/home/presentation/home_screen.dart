import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final name = await AuthStorage.getUserName();
    if (mounted && name != null) setState(() => _userName = name);
  }

  Future<void> _logout() async {
    await AuthApi.logout();
    if (mounted) context.go('/auth/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      backgroundColor: AppTheme.primary,
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: _logout,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryDark, AppTheme.primary],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Hello, $_userName! 👋',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'How are you feeling today?',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emergency SOS button
          _EmergencyCard(),
          const SizedBox(height: 20),
          const Text('Health Features',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _FeatureCard(
                icon: Icons.document_scanner,
                title: 'Scan Prescription',
                subtitle: 'OCR + AI analysis',
                color: const Color(0xFF1565C0),
                onTap: () => context.go('/home/prescriptions/scan'),
              ),
              _FeatureCard(
                icon: Icons.medication,
                title: 'Medicines',
                subtitle: 'Search & info',
                color: const Color(0xFF00695C),
                onTap: () => context.go('/home/medicines'),
              ),
              _FeatureCard(
                icon: Icons.alarm,
                title: 'Reminders',
                subtitle: 'Medication schedule',
                color: const Color(0xFFE65100),
                onTap: () => context.go('/home/reminders'),
              ),
              _FeatureCard(
                icon: Icons.monitor_heart,
                title: 'Health Monitor',
                subtitle: 'Track vitals',
                color: const Color(0xFF6A1B9A),
                onTap: () => context.go('/home/health'),
              ),
              _FeatureCard(
                icon: Icons.folder_shared,
                title: 'My Records',
                subtitle: 'Lab & prescriptions',
                color: const Color(0xFF0277BD),
                onTap: () => context.go('/home/records'),
              ),
              _FeatureCard(
                icon: Icons.family_restroom,
                title: 'Family',
                subtitle: 'Health profiles',
                color: const Color(0xFF558B2F),
                onTap: () => context.go('/home/family'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('AI & Services',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _WideCard(
            icon: Icons.psychology,
            title: 'AI Health Assistant',
            subtitle: 'Ask health & medication questions',
            color: AppTheme.secondary,
            onTap: () => context.go('/home/ai-chat'),
          ),
          const SizedBox(height: 10),
          _WideCard(
            icon: Icons.local_hospital,
            title: 'Nearby Services',
            subtitle: 'Hospitals, pharmacies & labs',
            color: AppTheme.success,
            onTap: () => context.go('/home/nearby'),
          ),
          const SizedBox(height: 10),
          _WideCard(
            icon: Icons.person,
            title: 'My Profile',
            subtitle: 'Health info & settings',
            color: const Color(0xFF546E7A),
            onTap: () => context.go('/home/profile'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EmergencyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/home/emergency'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.emergencyRed,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: AppTheme.emergencyRed.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: const Row(
          children: [
            Icon(Icons.emergency, color: Colors.white, size: 28),
            SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Emergency SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Tap to alert emergency contacts', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            Spacer(),
            Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _WideCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _WideCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
