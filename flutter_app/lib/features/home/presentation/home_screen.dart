// home_screen.dart — HealthNest · Premium Home Dashboard
// Pure UI/UX redesign (2026-07-30). Zero changes to business logic, APIs,
// navigation routes, state management, or existing functionality.
//
// ── Design principles ──────────────────────────────────────────────────────────
//  [D1]  8dp spatial grid  — all gaps are multiples of 4/8dp
//  [D2]  Compact header    — 120dp expanded height; first-name greeting only
//  [D3]  Search bar        — Material 3 tonal search surface below header
//  [D4]  Dashboard row     — scrollable stat chips (Today's Health)
//  [D5]  Landscape cards   — childAspectRatio 1.3 for 2-line safety
//  [D6]  Semantic colours  — per-feature accent tied to healthcare meaning
//  [D7]  Stagger entrance  — 700ms AnimationController drives 3 stagger offsets
//  [D8]  Tap scale         — _TapScaleCard provides 0.96 press-down feel
//  [D9]  Tab cross-fade    — 200ms FadeTransition between tabs
//  [D10] RepaintBoundary   — isolates body from SliverAppBar scroll repaints
//  [D11] WCAG AA           — Semantics labels on every interactive widget
//  [D12] Responsive        — 3-col on tablets ≥600dp, 2-col on phones

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/network/server_discovery.dart';
import 'package:vitapulse_ai/core/utils/auth_storage.dart';
import 'package:vitapulse_ai/features/auth/data/auth_api.dart';
import 'package:vitapulse_ai/features/home/presentation/app_drawer.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_elevation.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_spacing.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

// ── Layout constants ────────────────────────────────────────────────────────────
const double _kCardAspectRatio  = 1.3;           // [D5] landscape, overflow-safe
const double _kCardGap          = AppSpacing.x2; // [D1] 8dp
const double _kScreenPad        = AppSpacing.x4; // [D1] 16dp gutters
const double _kSectionGap       = AppSpacing.x3; // [D1] 12dp header→grid
const double _kSectionSpacing   = AppSpacing.x6; // [D1] 24dp between sections
const double _kTabletBreak      = 600.0;         // [D12] MD3 tablet breakpoint
const Duration _kTabAnim        = Duration(milliseconds: 200);  // [D9]
const Duration _kEntranceTotal  = Duration(milliseconds: 700);  // [D7]

int _cols(BuildContext ctx) =>
    MediaQuery.sizeOf(ctx).width >= _kTabletBreak ? 3 : 2; // [D12]

// ── Stagger helpers [D7] ────────────────────────────────────────────────────────
// Three stagger bands so the search bar, summary, and grid cascade in sequence.
Animation<double> _stagger(AnimationController ctrl, double from, double to) =>
    CurvedAnimation(parent: ctrl, curve: Interval(from, to, curve: Curves.easeOutCubic));

// ═══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN — shell
// ═══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {

  // ── State ─────────────────────────────────────────────────────────────────
  String  _userName        = 'User';
  String? _profileImageUrl;
  int     _selectedTab     = 0;
  bool    _loggingOut      = false;

  // [D9] Tab cross-fade controller
  late final AnimationController _tabCtrl;
  // [D7] Page entrance stagger controller (runs once)
  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = AnimationController(
        vsync: this, duration: _kTabAnim, value: 1.0);
    _entranceCtrl = AnimationController(
        vsync: this, duration: _kEntranceTotal);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUser();
      _entranceCtrl.forward(); // [D7] trigger entrance on first frame
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ── User load ─────────────────────────────────────────────────────────────
  Future<void> _loadUser() async {
    final name    = await AuthStorage.getUserName();
    final relPath = await AuthStorage.getProfileImageUrl();
    if (mounted) {
      setState(() {
        if (name != null) _userName = name;
        _profileImageUrl = _absUrl(relPath);
      });
    }
    try {
      final resp = await ApiClient.get('/users/me');
      final data = resp.data as Map<String, dynamic>;
      final freshRel = data['profile_image_url'] as String?;
      if (mounted) {
        setState(() {
          if (data['name'] != null) _userName = data['name'] as String;
          _profileImageUrl = _absUrl(freshRel);
        });
      }
      await AuthStorage.saveProfileImageUrl(freshRel);
    } catch (_) {}
  }

  static String? _absUrl(String? rel) {
    if (rel == null || rel.isEmpty) return null;
    final root = baseUrl.replaceFirst('/api/v1', '');
    return '$root/uploads/${rel.replaceAll(r'\', '/')}';
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      final outcome = await AuthApi.logout();
      if (!mounted) return;
      if (outcome == LogoutOutcome.localOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Signed out on this device. Server session could not be confirmed.',
            ),
          ),
        );
      }
      context.go('/auth/welcome');
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  void _onProfileMenu(String action) {
    switch (action) {
      case 'profile':    context.push('/home/profile');             break;
      case 'appearance': context.push('/home/settings/appearance'); break;
      case 'logout':     _logout();                                 break;
    }
  }

  void _switchTab(int i) {
    _tabCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _selectedTab = i);
      _tabCtrl.forward();
      // Re-run entrance when switching back to Home tab
      if (i == 0) _entranceCtrl.forward(from: 0);
    });
  }

  // ── Server setup (debug) ──────────────────────────────────────────────────
  Future<void> _showServerSetup() async {
    final cs       = Theme.of(context).colorScheme;
    final manualIp = await ServerDiscovery.getManualIp();
    final current  = ApiClient.activeBaseUrl ?? 'Auto-discovering…';
    if (!mounted) return;
    final ipCtrl = TextEditingController(text: manualIp ?? '');
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
          title: Row(children: [
            Icon(Icons.wifi, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Server Connection'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.brSm),
              child: Row(children: [
                Icon(Icons.link, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(current,
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text("Enter your PC's IP:",
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: ipCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.1.132',
                prefixIcon: Icon(Icons.computer, color: cs.primary),
                suffixText: ':8000',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: saving ? null : () async {
                await ServerDiscovery.clearManualIp();
                await ApiClient.rediscover();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Auto'),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final ip = ipCtrl.text.trim();
                if (ip.isEmpty) { Navigator.pop(ctx); return; }
                ss(() => saving = true);
                await ServerDiscovery.setManualIp(ip);
                await ApiClient.rediscover();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) _loadUser();
              },
              child: saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
    ipCtrl.dispose();
  }

  // ── Tab config ────────────────────────────────────────────────────────────
  static const _tabs = [
    (label: 'Home',     icon: Icons.home_outlined,       activeIcon: Icons.home_rounded),
    (label: 'Health',   icon: Icons.favorite_outline,    activeIcon: Icons.favorite_rounded),
    (label: 'AI Tools', icon: Icons.psychology_outlined, activeIcon: Icons.psychology_rounded),
    (label: 'Family',   icon: Icons.group_outlined,      activeIcon: Icons.group_rounded),
    (label: 'More',     icon: Icons.more_horiz_rounded,  activeIcon: Icons.more_horiz_rounded),
  ];

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      drawer: const AppDrawer(),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildAppBar()],
        body: RepaintBoundary( // [D10]
          child: FadeTransition( // [D9]
            opacity: _tabCtrl,
            child: _tabBody(),
          ),
        ),
      ),
      // [D11] WCAG: labelled SOS FAB
      floatingActionButton: Semantics(
        label: 'Emergency SOS — alert your emergency contacts immediately',
        button: true,
        child: FloatingActionButton(
          heroTag:         'sos-fab',
          onPressed:       () => context.push('/home/emergency'),
          backgroundColor: hc.emergency,
          foregroundColor: Colors.white,
          elevation:       4,
          tooltip:         'Emergency SOS',
          child: const Icon(Icons.emergency_rounded, size: 26),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Compact SliverAppBar [D2] ──────────────────────────────────────────────
  // 120dp expanded (was 150/185). Saves another 30dp of chrome,
  // allowing the search bar + first summary card above the fold.
  SliverAppBar _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return SliverAppBar(
      expandedHeight:  120,
      toolbarHeight:   56,
      floating:        false,
      pinned:          true,
      elevation:       0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: cs.primary,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon:    const Icon(Icons.menu_rounded, color: Colors.white),
          tooltip: 'Open drawer',
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      actions: [
        if (kDebugMode)
          IconButton(
            icon:    const Icon(Icons.wifi_outlined, color: Colors.white70),
            tooltip: 'Server connection',
            onPressed: _showServerSetup,
          ),
        IconButton(
          icon:    const Icon(Icons.notifications_outlined, color: Colors.white),
          tooltip: 'Notifications',
          onPressed: () {}, // placeholder — screen not yet implemented
        ),
        _buildProfileMenu(),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _AppBarBackground(
          userName:        _userName,
          profileImageUrl: _profileImageUrl,
          onProfileMenu:   _onProfileMenu,
          onChipTap: {
            'eRx':          () => context.push('/home/eprescriptions'),
            'Reminders':    () => context.push('/home/reminders'),
            'Insights':     () => context.push('/home/insights'),
            'Interactions': () => context.push('/home/interactions'),
          },
        ),
      ),
    );
  }

  // Inline profile menu trigger (avatar in actions row)
  Widget _buildProfileMenu() => Semantics(
    label:  'Profile menu for $_userName',
    button: true,
    child: PopupMenuButton<String>(
      offset:  const Offset(0, 52),
      tooltip: 'Profile',
      onSelected: _onProfileMenu,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'profile',
          child: Row(children: [
            Icon(Icons.person_outline, size: 18),
            SizedBox(width: 10),
            Text('My Profile'),
          ]),
        ),
        PopupMenuItem(
          value: 'appearance',
          child: Row(children: [
            Icon(Icons.palette_outlined, size: 18),
            SizedBox(width: 10),
            Text('Appearance'),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout, size: 18, color: Color(0xFFDC2626)),
            SizedBox(width: 10),
            Text('Sign Out', style: TextStyle(color: Color(0xFFDC2626))),
          ]),
        ),
      ],
      child: _ProfileAvatar(
        imageUrl: _profileImageUrl,
        name:     _userName,
        radius:   18, // [D2] reduced from 22
      ),
    ),
  );

  // ── Bottom navigation [D9] ─────────────────────────────────────────────────
  Widget _buildBottomNav() => NavigationBar(
    selectedIndex:         _selectedTab,
    onDestinationSelected: _switchTab,
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    destinations: _tabs.map((t) => NavigationDestination(
      icon:         Icon(t.icon),
      selectedIcon: Icon(t.activeIcon),
      label:        t.label,
    )).toList(),
  );

  // ── Tab body ──────────────────────────────────────────────────────────────
  Widget _tabBody() => switch (_selectedTab) {
    0 => _HomeTab(userName: _userName, entranceCtrl: _entranceCtrl),
    1 => const _HealthTab(),
    2 => const _AiTab(),
    3 => const _FamilyTab(),
    4 => const _MoreTab(),
    _ => _HomeTab(userName: _userName, entranceCtrl: _entranceCtrl),
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// APP BAR BACKGROUND [D2]
// ═══════════════════════════════════════════════════════════════════════════════

class _AppBarBackground extends StatelessWidget {
  final String  userName;
  final String? profileImageUrl;
  final void Function(String) onProfileMenu;
  final Map<String, VoidCallback> onChipTap;

  const _AppBarBackground({
    required this.userName,
    required this.profileImageUrl,
    required this.onProfileMenu,
    required this.onChipTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now().hour;
    final greeting = now < 12 ? 'Good Morning' : now < 17 ? 'Good Afternoon' : 'Good Evening';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
          colors: [
            Color.lerp(cs.primary, Colors.black, 0.25)!,
            cs.primary,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisAlignment:  MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [D2] greeting line — two-row compact design
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$greeting 👋',
                          style: const TextStyle(
                            color:         Colors.white70,
                            fontSize:      12,
                            fontWeight:    FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          userName.split(' ').first,
                          style: const TextStyle(
                            color:         Colors.white,
                            fontSize:      20,
                            fontWeight:    FontWeight.w800,
                            letterSpacing: -0.4,
                            height:        1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // [D2] status pill — HealthNest branding in header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:        Colors.white.withValues(alpha: 0.18),
                      borderRadius: AppRadius.brFull,
                      border:       Border.all(color: Colors.white24),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.health_and_safety_outlined,
                          size: 11, color: Colors.white70),
                      SizedBox(width: 4),
                      Text(
                        'HealthNest',
                        style: TextStyle(
                            fontSize: 10, color: Colors.white70,
                            fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // [D2] quick-action chips row
              SizedBox(
                height: 26,
                child: ListView.separated(
                  scrollDirection:   Axis.horizontal,
                  physics:           const BouncingScrollPhysics(),
                  itemCount:         onChipTap.length,
                  separatorBuilder:  (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final e = onChipTap.entries.elementAt(i);
                    return _HeaderChip(label: e.key, onTap: e.value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 0 — HOME DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

class _HomeTab extends StatelessWidget {
  final String             userName;
  final AnimationController entranceCtrl;
  const _HomeTab({required this.userName, required this.entranceCtrl});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hc   = HealthcareColors.of(context);
    final cols = _cols(context);

    // [D7] three stagger bands
    final aSearch  = _stagger(entranceCtrl, 0.00, 0.45);
    final aSummary = _stagger(entranceCtrl, 0.15, 0.60);
    final aCards   = _stagger(entranceCtrl, 0.30, 1.00);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          _kScreenPad, _kScreenPad, _kScreenPad, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Search bar [D3][D7] ─────────────────────────────────────────
          _FadeSlide(animation: aSearch, child: const _HomeSearchBar()),

          const SizedBox(height: 16),

          // ── Today's Health summary [D4][D7] ─────────────────────────────
          _FadeSlide(
            animation: aSummary,
            child: const _DashboardSummaryRow(),
          ),

          const SizedBox(height: _kSectionSpacing),

          // ── Quick Access [D5][D7] ─────────────────────────────────────
          _FadeSlide(
            animation: aCards,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon:     Icons.bolt_rounded,
                  title:    'Quick Access',
                  subtitle: 'Frequently used tools',
                  color:    cs.primary,
                ),
                const SizedBox(height: _kSectionGap),
                // [D5][D12] responsive grid
                GridView.count(
                  crossAxisCount:   cols,
                  shrinkWrap:       true,
                  physics:          const NeverScrollableScrollPhysics(),
                  mainAxisSpacing:  _kCardGap,
                  crossAxisSpacing: _kCardGap,
                  childAspectRatio: _kCardAspectRatio,
                  children: [
                    // [D6] per-feature semantic accent colours
                    _ActionCard(
                      icon:      Icons.psychology_rounded,
                      title:     'AI Health\nAssistant',
                      subtitle:  'Ask anything',
                      color:     hc.aiAccent,
                      isPrimary: true,
                      onTap:     () => context.push('/home/ai-chat'),
                    ),
                    _ActionCard(
                      icon:    Icons.document_scanner_rounded,
                      title:   'Scan\nPrescription',
                      subtitle: 'OCR + AI',
                      color:   hc.prescription,
                      onTap:   () => context.push('/home/prescriptions/scan'),
                    ),
                    _ActionCard(
                      icon:    Icons.qr_code_2_rounded,
                      title:   'ePrescription',
                      subtitle: 'Scan eRx QR',
                      color:   cs.primary,
                      onTap:   () => context.push('/home/eprescriptions'),
                    ),
                    _ActionCard(
                      icon:    Icons.medical_services_rounded,
                      title:   'Symptom\nChecker',
                      subtitle: 'AI triage',
                      color:   cs.secondary,
                      onTap:   () => context.push('/home/symptoms'),
                    ),
                    _ActionCard(
                      icon:    Icons.alarm_rounded,
                      title:   'Reminders',
                      subtitle: 'Medication alerts',
                      color:   hc.vitaWarning,
                      onTap:   () => context.push('/home/reminders'),
                    ),
                    _ActionCard(
                      icon:    Icons.monitor_heart_rounded,
                      title:   'Health\nMonitor',
                      subtitle: 'Track vitals',
                      color:   hc.vitaGood,
                      onTap:   () => context.push('/home/health'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: _kSectionSpacing),

          // ── All Features [D7] ─────────────────────────────────────────
          _FadeSlide(
            animation: aCards,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  icon:     Icons.grid_view_rounded,
                  title:    'All Features',
                  subtitle: 'Complete toolbox',
                  color:    cs.onSurfaceVariant,
                ),
                const SizedBox(height: _kSectionGap),
                _FeatureChipBar(
                  chips: const [
                    _Chip(Icons.folder_copy_rounded,     'Records'),
                    _Chip(Icons.medication_rounded,       'Medicines'),
                    _Chip(Icons.insights_rounded,         'Insights'),
                    _Chip(Icons.biotech_rounded,          'Interactions'),
                    _Chip(Icons.science_rounded,          'Lab AI'),
                    _Chip(Icons.location_on_rounded,      'Nearby'),
                    _Chip(Icons.family_restroom_rounded,  'Family'),
                    _Chip(Icons.palette_outlined,         'Themes'),
                  ],
                  onTaps: [
                    () => context.push('/home/records'),
                    () => context.push('/home/medicines'),
                    () => context.push('/home/insights'),
                    () => context.push('/home/interactions'),
                    () => context.push('/home/lab-analysis'),
                    () => context.push('/home/nearby'),
                    () => context.push('/home/family'),
                    () => context.push('/home/settings/appearance'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — HEALTH
// ═══════════════════════════════════════════════════════════════════════════════

class _HealthTab extends StatelessWidget {
  const _HealthTab();

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hc   = HealthcareColors.of(context);
    final cols = _cols(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kScreenPad, _kScreenPad, _kScreenPad, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader(
            icon: Icons.assignment_outlined,
            title: 'Prescriptions & Records',
            color: hc.prescription),
        const SizedBox(height: _kSectionGap),
        _cardGrid(cols, [
          _ActionCard(
              icon: Icons.document_scanner_rounded,
              title: 'Scan Prescription', subtitle: 'OCR + AI analysis',
              color: hc.prescription,
              onTap: () => context.push('/home/prescriptions/scan')),
          _ActionCard(
              icon: Icons.qr_code_2_rounded,
              title: 'ePrescription', subtitle: 'Scan & validate eRx',
              color: cs.primary,
              onTap: () => context.push('/home/eprescriptions')),
          _ActionCard(
              icon: Icons.folder_copy_rounded,
              title: 'My Records', subtitle: 'Lab & prescriptions',
              color: hc.radiology,
              onTap: () => context.push('/home/records')),
        ]),
        const SizedBox(height: _kSectionSpacing),
        _SectionHeader(
            icon: Icons.medication_outlined,
            title: 'Medicines & Reminders',
            color: hc.vitaWarning),
        const SizedBox(height: _kSectionGap),
        _cardGrid(cols, [
          _ActionCard(
              icon: Icons.medication_rounded,
              title: 'Medicine Search', subtitle: 'TGA AU database',
              color: cs.primary,
              onTap: () => context.push('/home/medicines')),
          _ActionCard(
              icon: Icons.alarm_rounded,
              title: 'Reminders', subtitle: 'Medication schedule',
              color: hc.vitaWarning,
              onTap: () => context.push('/home/reminders')),
        ]),
        const SizedBox(height: _kSectionSpacing),
        _SectionHeader(
            icon: Icons.monitor_heart_outlined,
            title: 'Health Monitoring',
            color: hc.vitaGood),
        const SizedBox(height: _kSectionGap),
        _cardGrid(cols, [
          _ActionCard(
              icon: Icons.monitor_heart_rounded,
              title: 'Health Monitor', subtitle: 'Track vitals',
              color: hc.vitaGood,
              onTap: () => context.push('/home/health')),
          _ActionCard(
              icon: Icons.insights_rounded,
              title: 'Health Insights', subtitle: 'AI predictive alerts',
              color: hc.prescription,
              onTap: () => context.push('/home/insights')),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — AI TOOLS
// ═══════════════════════════════════════════════════════════════════════════════

class _AiTab extends StatelessWidget {
  const _AiTab();

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hc   = HealthcareColors.of(context);
    final cols = _cols(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kScreenPad, _kScreenPad, _kScreenPad, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader(
            icon: Icons.psychology_outlined,
            title: 'AI Health Assistant',
            subtitle: 'Powered by Claude AI',
            color: hc.aiAccent),
        const SizedBox(height: _kSectionGap),
        _WideActionCard(
          icon: Icons.psychology_rounded,
          title: 'AI Health Chat',
          subtitle: 'Ask any health or medication question',
          color: hc.aiAccent,
          badge: 'Claude AI',
          onTap: () => context.push('/home/ai-chat'),
        ),
        const SizedBox(height: _kSectionSpacing),
        _SectionHeader(
            icon: Icons.biotech_outlined,
            title: 'Diagnostic Tools',
            subtitle: 'AI-powered clinical analysis',
            color: cs.primary),
        const SizedBox(height: _kSectionGap),
        _cardGrid(cols, [
          _ActionCard(
              icon: Icons.biotech_rounded,
              title: 'Drug Interactions', subtitle: 'AI safety analysis',
              color: hc.prescription,
              onTap: () => context.push('/home/interactions')),
          _ActionCard(
              icon: Icons.medical_services_rounded,
              title: 'Symptom Checker', subtitle: 'AI triage guidance',
              color: cs.secondary,
              onTap: () => context.push('/home/symptoms')),
          _ActionCard(
              icon: Icons.science_rounded,
              title: 'Lab Report AI', subtitle: 'Explain test results',
              color: hc.labReport,
              onTap: () => context.push('/home/lab-analysis')),
          _ActionCard(
              icon: Icons.insights_rounded,
              title: 'Health Insights', subtitle: 'Predictive alerts',
              color: hc.radiology,
              onTap: () => context.push('/home/insights')),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — FAMILY
// ═══════════════════════════════════════════════════════════════════════════════

class _FamilyTab extends StatelessWidget {
  const _FamilyTab();

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hc   = HealthcareColors.of(context);
    final cols = _cols(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kScreenPad, _kScreenPad, _kScreenPad, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader(
            icon: Icons.group_outlined,
            title: 'Family Health',
            subtitle: 'Manage everyone in one place',
            color: hc.discharge),
        const SizedBox(height: _kSectionGap),
        _WideActionCard(
          icon: Icons.family_restroom_rounded,
          title: 'Family Health Profiles',
          subtitle: 'Manage records for your whole family',
          color: hc.discharge,
          onTap: () => context.push('/home/family'),
        ),
        const SizedBox(height: AppSpacing.x2),
        _WideActionCard(
          icon: Icons.qr_code_2_rounded,
          title: 'Shared ePrescriptions',
          subtitle: 'View prescriptions shared with you',
          color: cs.primary,
          onTap: () => context.push('/home/eprescriptions'),
        ),
        const SizedBox(height: _kSectionSpacing),
        _SectionHeader(
            icon: Icons.location_on_outlined,
            title: 'Nearby & Safety',
            color: cs.primary),
        const SizedBox(height: _kSectionGap),
        _cardGrid(cols, [
          _ActionCard(
              icon: Icons.location_on_rounded,
              title: 'Nearby Services', subtitle: 'Hospitals & pharmacies',
              color: hc.discharge,
              onTap: () => context.push('/home/nearby')),
          _ActionCard(
              icon: Icons.biotech_rounded,
              title: 'Drug Interactions', subtitle: 'Check medicine safety',
              color: hc.prescription,
              onTap: () => context.push('/home/interactions')),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4 — MORE
// ═══════════════════════════════════════════════════════════════════════════════

class _MoreTab extends StatelessWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final hc   = HealthcareColors.of(context);
    final cols = _cols(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kScreenPad, _kScreenPad, _kScreenPad, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Profile & preferences',
            color: cs.primary),
        const SizedBox(height: _kSectionGap),
        _WideActionCard(
          icon: Icons.person_rounded,
          title: 'My Profile',
          subtitle: 'Health info, photo & personal details',
          color: cs.primary,
          onTap: () => context.push('/home/profile'),
        ),
        const SizedBox(height: AppSpacing.x2),
        Consumer(builder: (ctx, ref, _) {
          final variant = ref.watch(themeManagerProvider).variant;
          return _WideActionCard(
            icon:     Icons.palette_outlined,
            title:    'Appearance',
            subtitle: variant.label,
            color:    cs.secondary,
            onTap:    () => context.push('/home/settings/appearance'),
          );
        }),
        const SizedBox(height: _kSectionSpacing),
        _SectionHeader(
            icon: Icons.explore_outlined,
            title: 'Explore All Features',
            subtitle: 'Everything HealthNest offers',
            color: cs.primary),
        const SizedBox(height: _kSectionGap),
        _cardGrid(cols, [
          _ActionCard(
              icon: Icons.document_scanner_rounded,
              title: 'Scan Prescription', subtitle: 'OCR + AI analysis',
              color: hc.prescription,
              onTap: () => context.push('/home/prescriptions/scan')),
          _ActionCard(
              icon: Icons.folder_copy_rounded,
              title: 'My Records', subtitle: 'Lab & prescriptions',
              color: hc.radiology,
              onTap: () => context.push('/home/records')),
          _ActionCard(
              icon: Icons.monitor_heart_rounded,
              title: 'Health Monitor', subtitle: 'Track vitals',
              color: hc.vitaGood,
              onTap: () => context.push('/home/health')),
          _ActionCard(
              icon: Icons.alarm_rounded,
              title: 'Reminders', subtitle: 'Medication schedule',
              color: hc.vitaWarning,
              onTap: () => context.push('/home/reminders')),
          _ActionCard(
              icon: Icons.science_rounded,
              title: 'Lab Report AI', subtitle: 'Explain results',
              color: hc.labReport,
              onTap: () => context.push('/home/lab-analysis')),
          _ActionCard(
              icon: Icons.location_on_rounded,
              title: 'Nearby Services', subtitle: 'Hospitals & pharmacies',
              color: hc.discharge,
              onTap: () => context.push('/home/nearby')),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED GRID BUILDER
// ═══════════════════════════════════════════════════════════════════════════════

Widget _cardGrid(int cols, List<Widget> children) => GridView.count(
  crossAxisCount:   cols,
  shrinkWrap:       true,
  physics:          const NeverScrollableScrollPhysics(),
  mainAxisSpacing:  _kCardGap,
  crossAxisSpacing: _kCardGap,
  childAspectRatio: _kCardAspectRatio,
  children: children,
);

// ═══════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ── [D7] Fade + Slide wrapper ──────────────────────────────────────────────────
// Wraps any widget in a simultaneous FadeTransition + SlideTransition driven
// by the stagger animation so sections cascade onto screen smoothly.
class _FadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _FadeSlide({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.04), // subtle — 4% of widget height
        end:   Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
}

// ── [D3] Search bar ────────────────────────────────────────────────────────────
// Material 3 tonal search surface. Navigates to medicines search on tap
// (medicine search has the most complete search experience in the app).
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label:  'Search medicines, prescriptions, and more',
      button: true,
      child: GestureDetector(
        onTap: () => context.push('/home/medicines'),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color:        cs.surfaceContainerHighest.withValues(alpha: 0.75),
            borderRadius: AppRadius.brFull,
            boxShadow:    AppElevation.level1,
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Search medicines, prescriptions…',
                  style: TextStyle(
                    fontSize:   14,
                    color:      cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Microphone affordance matches Material 3 SearchBar spec
              Icon(Icons.mic_outlined, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── [D4] Today's Health summary row ───────────────────────────────────────────
// Five compact stat chips loaded from the existing health-metrics/summary
// endpoint. Shows '--' while loading or on error — never breaks.
class _DashboardSummaryRow extends StatefulWidget {
  const _DashboardSummaryRow();
  @override
  State<_DashboardSummaryRow> createState() => _DashboardSummaryRowState();
}

class _DashboardSummaryRowState extends State<_DashboardSummaryRow> {
  // Health metric values — populated from /health-metrics/summary
  String _heartRate  = '--';
  String _bp         = '--';
  String _bloodSugar = '--';
  String _weight     = '--';
  // Reminder count — populated from /reminders/
  String _medCount   = '--';
  bool   _loaded     = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Fire both API calls in parallel; each handles its own error so a
    // failure in one does not prevent the other from showing its data.
    Map<String, dynamic>? summary;
    List<dynamic>?        reminders;

    await Future.wait([
      ApiClient.get('/health-metrics/summary')
          .then<void>((r) { summary = r.data as Map<String, dynamic>; })
          .catchError((_) {}),
      ApiClient.get('/reminders/')
          .then((r) {
            final d = r.data;
            if (d is List) reminders = d;
          })
          .catchError((_) {}),
    ]);

    if (!mounted) return;
    setState(() {
      if (summary != null) {
        final hr  = _val(summary!, 'heart_rate');
        final sys = _val(summary!, 'blood_pressure');
        final dia = _val2(summary!, 'blood_pressure');
        final bs  = _val(summary!, 'blood_sugar');
        final wt  = _val(summary!, 'weight');

        if (hr  != null) _heartRate  = '${hr.toStringAsFixed(0)} bpm';
        if (sys != null && dia != null) {
          _bp = '${sys.toStringAsFixed(0)}/${dia.toStringAsFixed(0)}';
        } else if (sys != null) {
          _bp = sys.toStringAsFixed(0);
        }
        if (bs != null) _bloodSugar = '${bs.toStringAsFixed(0)} mg/dL';
        if (wt != null) _weight     = '${wt.toStringAsFixed(1)} kg';
      }
      if (reminders != null) {
        final n = reminders!.length;
        _medCount = n == 0 ? 'None' : '$n active';
      }
      _loaded = true;
    });
  }

  // Helper: safely read latest_value for a metric type key
  double? _val(Map<String, dynamic> m, String key) {
    final entry = m[key];
    if (entry is Map<String, dynamic>) {
      final v = entry['latest_value'];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  // Helper: safely read latest_value2 (diastolic BP)
  double? _val2(Map<String, dynamic> m, String key) {
    final entry = m[key];
    if (entry is Map<String, dynamic>) {
      final v = entry['latest_value2'];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "Today's Health",
              style: tt.titleSmall!.copyWith(
                fontWeight: FontWeight.w700,
                color:      cs.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color:  hc.vitaGood,
                shape:  BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: hc.vitaGood.withValues(alpha: 0.4),
                      blurRadius: 4),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 86,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _StatChip(
                icon:  Icons.alarm_rounded,
                color: hc.vitaWarning,
                label: 'Medicines',
                value: _loaded ? _medCount : '…',
                onTap: () => context.push('/home/reminders'),
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon:  Icons.monitor_heart_rounded,
                color: hc.vitaCritical,
                label: 'Heart Rate',
                value: _loaded ? _heartRate : '…',
                onTap: () => context.push('/home/health'),
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon:  Icons.favorite_rounded,
                color: hc.prescription,
                label: 'Blood Pressure',
                value: _loaded ? _bp : '…',
                onTap: () => context.push('/home/health'),
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon:  Icons.water_drop_rounded,
                color: hc.labReport,
                label: 'Blood Sugar',
                value: _loaded ? _bloodSugar : '…',
                onTap: () => context.push('/home/health'),
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon:  Icons.scale_rounded,
                color: hc.discharge,
                label: 'Weight',
                value: _loaded ? _weight : '…',
                onTap: () => context.push('/home/health'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Single stat chip in the summary row
class _StatChip extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       label;
  final String       value;
  final VoidCallback onTap;
  const _StatChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      label:  '$label: $value',
      button: true,
      child: _TapScaleCard(
        onTap: onTap,
        child: Container(
          width:   110,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:        cs.surface,
            borderRadius: AppRadius.brLg,
            boxShadow:    AppElevation.level1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color:        color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brXs,
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: tt.titleSmall!.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize:   12,
                      height:     1.1,
                      color:      cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: tt.labelSmall!.copyWith(
                      color:    cs.onSurfaceVariant,
                      fontSize: 10,
                      height:   1.1,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────
// Optional [subtitle] adds a muted description line below the title.
class _SectionHeader extends StatelessWidget {
  final IconData  icon;
  final String    title;
  final String?   subtitle;
  final Color     color;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color:        color.withValues(alpha: 0.12),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleSmall!.copyWith(
                  color:      color,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: tt.bodySmall!.copyWith(
                    color:    cs.onSurfaceVariant,
                    fontSize: 11,
                    height:   1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Header chip [D2] ───────────────────────────────────────────────────────────
class _HeaderChip extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _HeaderChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    label:  label,
    button: true,
    child: Material(
      color:        Colors.white.withValues(alpha: 0.15),
      borderRadius: AppRadius.brFull,
      child: InkWell(
        onTap:        onTap,
        borderRadius: AppRadius.brFull,
        child: Container(
          height:  26,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            borderRadius: AppRadius.brFull,
            border: Border.fromBorderSide(
                BorderSide(color: Colors.white24)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize:   10.5,
              color:      Colors.white,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Feature chip bar ───────────────────────────────────────────────────────────
class _Chip {
  final IconData icon;
  final String   label;
  const _Chip(this.icon, this.label);
}

class _FeatureChipBar extends StatelessWidget {
  final List<_Chip>        chips;
  final List<VoidCallback> onTaps;
  const _FeatureChipBar({required this.chips, required this.onTaps});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Semantics(
          label:  chips[i].label,
          button: true,
          child: _TapScaleCard(
            onTap: onTaps[i],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              decoration: BoxDecoration(
                color:        cs.surface,
                borderRadius: AppRadius.brFull,
                boxShadow:    AppElevation.level1,
                border:       Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chips[i].icon, size: 13, color: cs.primary),
                  const SizedBox(width: 5),
                  Text(
                    chips[i].label,
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color:      cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize:   11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── [D8] Tap scale wrapper ─────────────────────────────────────────────────────
// Gives a subtle 0.96 press-down on any tappable element. Uses
// AnimatedScale so it leverages Flutter's optimised rasterisation cache.
class _TapScaleCard extends StatefulWidget {
  final Widget       child;
  final VoidCallback onTap;
  const _TapScaleCard({required this.child, required this.onTap});
  @override
  State<_TapScaleCard> createState() => _TapScaleCardState();
}

class _TapScaleCardState extends State<_TapScaleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sc;
  late final Animation<double>    _scale;

  @override
  void initState() {
    super.initState();
    _sc    = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
    _scale = Tween<double>(begin: 1.0, end: 0.955).animate(
        CurvedAnimation(parent: _sc, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown:   (_) => _sc.forward(),
    onTapUp:     (_) { _sc.reverse(); widget.onTap(); },
    onTapCancel: ()  => _sc.reverse(),
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

// ── Action card [D5][D6][D8] ───────────────────────────────────────────────────
// Uses MainAxisAlignment.spaceBetween so the column fills the GridView cell.
// The icon group sits at the top and text at the bottom — no overflow
// regardless of whether the title is 1 or 2 lines.
class _ActionCard extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        color;
  final VoidCallback onTap;
  final bool         isPrimary;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      label:  '$title — $subtitle',
      button: true,
      child: _TapScaleCard( // [D8] press-down scale
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:        cs.surface,
            borderRadius: AppRadius.brLg,
            boxShadow: isPrimary ? AppElevation.level2 : AppElevation.level1,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.brLg,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment:  MainAxisAlignment.start,
                  children: [
                    // Icon row with optional chevron
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color:        color.withValues(alpha: 0.12),
                            borderRadius: AppRadius.brSm,
                          ),
                          child: Icon(icon, color: color, size: 17),
                        ),
                        const Spacer(),
                        if (isPrimary)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Icon(Icons.arrow_forward_ios_rounded,
                                size: 10, color: color.withValues(alpha: 0.5)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Text group
                    Text(
                      title,
                      style: tt.bodySmall!.copyWith(
                        fontWeight: FontWeight.w700,
                        height:     1.2,
                        fontSize:   12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.labelSmall!.copyWith(
                        color:    cs.onSurfaceVariant,
                        fontSize: 10,
                        height:   1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Wide action card ───────────────────────────────────────────────────────────
class _WideActionCard extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        color;
  final VoidCallback onTap;
  final String?      badge;

  const _WideActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      label:  '$title — $subtitle',
      button: true,
      child: _TapScaleCard( // [D8]
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:        cs.surface,
            borderRadius: AppRadius.brLg,
            boxShadow:    AppElevation.level1,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.brLg,
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:        color.withValues(alpha: 0.12),
                        borderRadius: AppRadius.brMd,
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(title,
                                  style: tt.titleSmall!.copyWith(
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (badge != null)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color:        color.withValues(alpha: 0.12),
                                  borderRadius: AppRadius.brSm,
                                ),
                                child: Text(badge!,
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: color)),
                              ),
                          ]),
                          Text(subtitle,
                              style: tt.bodySmall!.copyWith(
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Profile avatar ─────────────────────────────────────────────────────────────
class _ProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final String  name;
  final double  radius;
  const _ProfileAvatar(
      {required this.imageUrl, required this.name, this.radius = 18});

  String get _initials => name.trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
      .join();

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      border: Border.fromBorderSide(
          BorderSide(color: Colors.white38, width: 1.5)),
    ),
    child: CircleAvatar(
      radius:          radius,
      backgroundColor: Colors.white24,
      child: imageUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl:    imageUrl!,
                width:       radius * 2,
                height:      radius * 2,
                fit:         BoxFit.cover,
                placeholder: (_, __) => _fallback,
                errorWidget: (_, __, ___) => _fallback,
              ),
            )
          : _fallback,
    ),
  );

  Widget get _fallback => Center(
    child: Text(
      _initials,
      style: TextStyle(
        fontSize:   radius * 0.62,
        fontWeight: FontWeight.w700,
        color:      Colors.white,
      ),
    ),
  );
}
