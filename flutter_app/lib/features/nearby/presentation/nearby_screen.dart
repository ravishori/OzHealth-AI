import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';
import 'package:vitapulse_ai/theme/theme_extensions.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Position? _gpsPosition;
  String _locationSource = 'default';
  String _locationLabel = 'Melbourne, VIC (default)';

  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;

  final List<List<_NearbyPlace>> _results = [[], [], [], []];
  final List<bool> _tabLoading = [false, false, false, false];
  final List<bool> _tabLoaded = [false, false, false, false];
  /// ok | cached | degraded | empty (genuine zero results)
  final List<String> _tabStatus = ['ok', 'ok', 'ok', 'ok'];
  final List<String?> _tabMessage = [null, null, null, null];

  static const List<String> _types = ['hospital', 'pharmacy', 'lab', 'gp'];
  static const List<String> _tabLabels = [
    'Hospitals',
    'Pharmacies',
    'Labs',
    'GPs',
  ];
  static const List<String> _tabEmptyLabels = [
    'hospitals',
    'pharmacies',
    'labs',
    'GPs',
  ];
  static const List<IconData> _tabIcons = [
    Icons.local_hospital_outlined,
    Icons.local_pharmacy_outlined,
    Icons.science_outlined,
    Icons.medical_services_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this)
      ..addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final i = _tabController.index;
      if (!_tabLoaded[i]) _fetchTab(i);
    }
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.medium),
          ).timeout(const Duration(seconds: 10));
          if (mounted) {
            setState(() {
              _gpsPosition = pos;
              _locationSource = 'gps';
              _locationLabel = 'Your GPS location';
            });
          }
        }
      }
    } catch (_) {
      // GPS failed — fall through to default
    }
    await _fetchTab(0);
  }

  Future<void> _searchLocation(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() => _searching = true);

    final bool isPostcode = RegExp(r'^\d{4}$').hasMatch(trimmed);
    final params = <String, dynamic>{
      if (isPostcode) 'postcode': trimmed else 'city': trimmed,
    };

    try {
      final resp =
          await ApiClient.get('/nearby/geocode', queryParameters: params);
      final data = resp.data as Map<String, dynamic>;

      if (data['found'] == true) {
        if (mounted) {
          setState(() {
            _locationSource = 'search';
            _locationLabel = data['label']?.toString() ?? trimmed;
            _gpsPosition = null;
            for (int i = 0; i < _tabLoaded.length; i++) {
              _tabLoaded[i] = false;
              _results[i] = [];
            }
          });
        }
        await _fetchTabWithCoords(
          _tabController.index,
          data['lat'] as double,
          data['lng'] as double,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  data['error']?.toString() ?? 'Location not found.'),
            ),
          );
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.response?.data?['detail']?.toString() ??
                'Search failed.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _applyNearbyPayload(int index, Map<String, dynamic> data) {
    final list = data['results'] as List<dynamic>? ?? [];
    final places = list
        .map((e) => _NearbyPlace.fromJson(e as Map<String, dynamic>))
        .toList();
    final status = data['status']?.toString() ?? 'ok';
    final message = data['message']?.toString() ?? data['error']?.toString();
    final source = data['location_source']?.toString() ?? _locationSource;

    String uiStatus = status;
    if (status == 'ok' && places.isEmpty) {
      uiStatus = 'empty';
    }

    setState(() {
      _results[index] = places;
      _tabLoaded[index] = true;
      _tabStatus[index] = uiStatus;
      _tabMessage[index] = message;
      if (index == 0) {
        _locationSource = source;
        _locationLabel = _labelForSource(source);
      }
    });
  }

  Future<void> _fetchTab(int index) async {
    setState(() => _tabLoading[index] = true);
    try {
      final queryParams = <String, dynamic>{'type': _types[index]};
      if (_gpsPosition != null) {
        queryParams['lat'] = _gpsPosition!.latitude;
        queryParams['lng'] = _gpsPosition!.longitude;
      }

      final response =
          await ApiClient.get('/nearby/', queryParameters: queryParams);
      final data = response.data as Map<String, dynamic>;
      if (mounted) _applyNearbyPayload(index, data);
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _tabLoaded[index] = true;
          _tabStatus[index] = 'degraded';
          _tabMessage[index] =
              'Nearby services are temporarily unavailable. Please try again shortly.';
          _results[index] = [];
        });
        final detail = e.response?.data;
        final safe = detail is Map && detail['detail'] is String
            ? detail['detail'] as String
            : 'Failed to load ${_tabLabels[index].toLowerCase()}.';
        // Avoid dumping raw provider exceptions
        final shown = safe.contains('Traceback') || safe.length > 180
            ? 'Failed to load ${_tabLabels[index].toLowerCase()}.'
            : safe;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(shown)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tabLoaded[index] = true;
          _tabStatus[index] = 'degraded';
          _tabMessage[index] =
              'Could not load ${_tabLabels[index].toLowerCase()}. Check your connection.';
          _results[index] = [];
        });
      }
    } finally {
      if (mounted) setState(() => _tabLoading[index] = false);
    }
  }

  Future<void> _fetchTabWithCoords(
      int index, double lat, double lng) async {
    setState(() => _tabLoading[index] = true);
    try {
      final response =
          await ApiClient.get('/nearby/', queryParameters: {
        'lat': lat,
        'lng': lng,
        'type': _types[index],
      });
      final data = response.data as Map<String, dynamic>;
      if (mounted) _applyNearbyPayload(index, data);
    } catch (_) {
      if (mounted) {
        setState(() {
          _tabLoaded[index] = true;
          _tabStatus[index] = 'degraded';
          _tabMessage[index] =
              'Nearby services are temporarily unavailable. Please try again shortly.';
          _results[index] = [];
        });
      }
    } finally {
      if (mounted) setState(() => _tabLoading[index] = false);
    }
  }

  String _labelForSource(String source) {
    return switch (source) {
      'gps' => 'Your GPS location',
      'profile' => 'Your profile address',
      'search' => _locationLabel,
      _ => 'Melbourne, VIC (default)',
    };
  }

  Future<void> _useGps() async {
    setState(() {
      _locationSource = 'gps';
      for (int i = 0; i < _tabLoaded.length; i++) {
        _tabLoaded[i] = false;
        _results[i] = [];
      }
    });
    await _initLocation();
  }

  Future<void> _openInMaps(_NearbyPlace place) async {
    final navUri =
        Uri.parse('google.navigation:q=${place.lat},${place.lng}&mode=d');
    if (await canLaunchUrl(navUri)) {
      await launchUrl(navUri);
      return;
    }
    final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${place.lat},${place.lng}'
        '&travelmode=driving');
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callPlace(_NearbyPlace place) async {
    if (place.phone == null || place.phone!.isEmpty) return;
    final uri = Uri.parse('tel:${place.phone!.replaceAll(' ', '')}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWebsite(_NearbyPlace place) async {
    String rawUrl;
    if (place.website != null && place.website!.isNotEmpty) {
      rawUrl = place.website!;
      if (!rawUrl.startsWith('http')) rawUrl = 'https://$rawUrl';
    } else {
      rawUrl =
          'https://www.google.com/search?q=${Uri.encodeComponent(place.name)}';
    }
    final uri = Uri.parse(rawUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ─────── UI ───────

  Widget _buildSearchBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.primary,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: cs.onPrimary),
            decoration: InputDecoration(
              hintText: 'Search by suburb, city, or postcode…',
              hintStyle:
                  TextStyle(color: cs.onPrimary.withValues(alpha: 0.60)),
              prefixIcon: _searching
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      ),
                    )
                  : Icon(Icons.search,
                      color: cs.onPrimary.withValues(alpha: 0.70)),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear,
                          color: cs.onPrimary.withValues(alpha: 0.60),
                          size: 20),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
                  IconButton(
                    icon: Icon(Icons.my_location,
                        color: cs.onPrimary.withValues(alpha: 0.70)),
                    tooltip: 'Use GPS',
                    onPressed: _useGps,
                  ),
                ],
              ),
              filled: true,
              fillColor: cs.onPrimary.withValues(alpha: 0.12),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: const OutlineInputBorder(
                borderRadius: AppRadius.brFull,
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: _searchLocation,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _buildLocationBadge(context),
        ],
      ),
    );
  }

  Widget _buildLocationBadge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final IconData icon;
    final Color color;
    switch (_locationSource) {
      case 'gps':
        icon = Icons.gps_fixed;
        color = cs.onPrimary;
        break;
      case 'profile':
        icon = Icons.person_pin_circle_outlined;
        color = cs.onPrimary.withValues(alpha: 0.85);
        break;
      case 'search':
        icon = Icons.search;
        color = cs.onPrimary.withValues(alpha: 0.85);
        break;
      default:
        icon = Icons.location_on_outlined;
        color = cs.onPrimary.withValues(alpha: 0.55);
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _locationLabel,
            style: TextStyle(color: color, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: cs.surfaceContainerHighest,
      highlightColor: cs.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 120,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: AppRadius.brLg,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    final status = _tabStatus[index];
    final isDegraded = status == 'degraded';
    final title = isDegraded
        ? 'Nearby ${_tabEmptyLabels[index]} unavailable'
        : 'No ${_tabEmptyLabels[index]} found nearby.';
    final subtitle = isDegraded
        ? (_tabMessage[index] ??
            'Live nearby data is temporarily unavailable. Please try again.')
        : 'Try expanding search radius or a different location.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isDegraded ? Icons.cloud_off_outlined : _tabIcons[index],
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _fetchTab(index),
              icon: const Icon(Icons.refresh),
              label: Text(isDegraded ? 'Retry' : 'Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, int index) {
    final status = _tabStatus[index];
    if (status != 'cached' && status != 'degraded') {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final isCached = status == 'cached';
    final bg = isCached
        ? cs.tertiaryContainer.withValues(alpha: 0.55)
        : cs.errorContainer.withValues(alpha: 0.45);
    final fg = isCached ? cs.onTertiaryContainer : cs.onErrorContainer;
    final text = _tabMessage[index] ??
        (isCached
            ? 'Showing previously loaded results.'
            : 'Nearby services are temporarily unavailable.');

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isCached ? Icons.history : Icons.warning_amber_outlined,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: fg, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => _fetchTab(index),
              child: Text('Retry', style: TextStyle(color: fg, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceTile(BuildContext context, _NearbyPlace place) {
    final cs = Theme.of(context).colorScheme;
    final hc = HealthcareColors.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + distance badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (place.address != null &&
                          place.address!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          place.address!,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _badge(
                      place.distanceLabel,
                      cs.primary,
                      cs.primaryContainer.withValues(alpha: 0.25),
                    ),
                    if (place.emergency) ...[
                      const SizedBox(height: 4),
                      _badge(
                        '24h Emergency',
                        hc.emergency,
                        hc.emergency.withValues(alpha: 0.08),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Travel time chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _infoChip(Icons.directions_walk_outlined,
                    '${place.walkMins} min walk', cs.secondary),
                _infoChip(Icons.directions_car_outlined,
                    '${place.driveMins} min drive', cs.tertiary),
                if (place.openingHours != null &&
                    place.openingHours!.isNotEmpty)
                  _infoChip(Icons.access_time_outlined,
                      place.openingHours!, cs.onSurfaceVariant),
                if (place.phone != null && place.phone!.isNotEmpty)
                  _infoChip(Icons.phone_outlined, place.phone!,
                      cs.onSurfaceVariant),
              ],
            ),

            const SizedBox(height: 10),

            // Action buttons
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openInMaps(place),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Maps'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                if (place.phone != null && place.phone!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _callPlace(place),
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openWebsite(place),
                  icon: const Icon(Icons.open_in_browser_outlined,
                      size: 16),
                  label: const Text('Web'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.brMd,
      ),
      child: Text(
        text,
        style: TextStyle(
            color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildTabContent(BuildContext context, int index) {
    if (_tabLoading[index]) return _buildSkeleton(context);

    final places = _results[index];

    if (places.isEmpty && _tabLoaded[index]) {
      return Column(
        children: [
          _buildStatusBanner(context, index),
          Expanded(child: _buildEmptyState(context, index)),
        ],
      );
    }
    if (places.isEmpty) return _buildSkeleton(context);

    return Column(
      children: [
        _buildStatusBanner(context, index),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _tabLoaded[index] = false;
                _results[index] = [];
              });
              await _fetchTab(index);
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: places.length,
              itemBuilder: (_, i) => _buildPlaceTile(context, places[i]),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Services'),
        centerTitle: true,
        leading: BackButton(onPressed: () => context.pop()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(130),
          child: Column(
            children: [
              _buildSearchBar(context),
              TabBar(
                controller: _tabController,
                tabs: List.generate(
                  4,
                  (i) => Tab(
                    icon: Icon(_tabIcons[i], size: 20),
                    text: _tabLabels[i],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(4, (i) => _buildTabContent(context, i)),
      ),
    );
  }
}

// ─────────────────────────── Data model ───────────────────────────

class _NearbyPlace {
  final String name;
  final double lat;
  final double lng;
  final String? phone;
  final String? address;
  final String? openingHours;
  final String? website;
  final double distanceKm;
  final int walkMins;
  final int driveMins;
  final bool emergency;

  const _NearbyPlace({
    required this.name,
    required this.lat,
    required this.lng,
    this.phone,
    this.address,
    this.openingHours,
    this.website,
    required this.distanceKm,
    required this.walkMins,
    required this.driveMins,
    required this.emergency,
  });

  String get distanceLabel {
    if (distanceKm < 1.0) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  factory _NearbyPlace.fromJson(Map<String, dynamic> json) {
    return _NearbyPlace(
      name: json['name']?.toString() ?? 'Unknown',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      phone: json['phone']?.toString(),
      address: json['address']?.toString(),
      openingHours: json['opening_hours']?.toString(),
      website: json['website']?.toString(),
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      walkMins: (json['walk_mins'] as num?)?.toInt() ?? 0,
      driveMins: (json['drive_mins'] as num?)?.toInt() ?? 0,
      emergency: json['emergency'] as bool? ?? false,
    );
  }
}
