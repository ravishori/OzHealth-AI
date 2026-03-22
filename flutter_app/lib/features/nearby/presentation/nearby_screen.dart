import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vitapulse_ai/core/network/api_client.dart';
import 'package:vitapulse_ai/core/theme/app_theme.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Position? _position;
  bool _locationLoading = true;
  String? _locationError;

  // Cached results per tab index: 0=hospital, 1=pharmacy, 2=lab
  final List<List<_NearbyPlace>> _results = [[], [], []];
  final List<bool> _tabLoading = [false, false, false];
  final List<bool> _tabLoaded = [false, false, false];

  static const List<String> _types = ['hospital', 'pharmacy', 'lab'];
  static const List<String> _tabLabels = ['Hospitals', 'Pharmacies', 'Labs'];
  static const List<IconData> _tabIcons = [
    Icons.local_hospital_outlined,
    Icons.local_pharmacy_outlined,
    Icons.science_outlined,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_onTabChanged);
    _initLocation();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final i = _tabController.index;
      if (!_tabLoaded[i] && _position != null) {
        _fetchTab(i);
      }
    }
  }

  Future<void> _initLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled. Please enable them in device settings.';
          _locationLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permission denied. We need your location to find nearby services.';
            _locationLoading = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError =
              'Location permission is permanently denied. Please enable it in your device settings.';
          _locationLoading = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _position = pos;
        _locationLoading = false;
      });
      await _fetchTab(0);
    } catch (e) {
      setState(() {
        _locationError = 'Could not determine your location. Please try again.';
        _locationLoading = false;
      });
    }
  }

  Future<void> _fetchTab(int index) async {
    if (_position == null) return;
    setState(() => _tabLoading[index] = true);
    try {
      final response = await ApiClient.get(
        '/nearby/',
        queryParameters: {
          'lat': _position!.latitude,
          'lng': _position!.longitude,
          'type': _types[index],
        },
      );
      final list = (response.data as List<dynamic>? ?? []);
      final places = list
          .map((e) => _NearbyPlace.fromJson(
              e as Map<String, dynamic>, _position!))
          .toList();
      if (mounted) {
        setState(() {
          _results[index] = places;
          _tabLoaded[index] = true;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = e.response?.data?['detail']?.toString() ??
            'Failed to load nearby ${_tabLabels[index].toLowerCase()}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Error loading ${_tabLabels[index].toLowerCase()}.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _tabLoading[index] = false);
    }
  }

  Future<void> _openInMaps(_NearbyPlace place) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps.')),
        );
      }
    }
  }

  Future<void> _callPlace(_NearbyPlace place) async {
    if (place.phone == null || place.phone!.isEmpty) return;
    final uri = Uri.parse('tel:${place.phone!.replaceAll(' ', '')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _buildLocationError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off_outlined,
                size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              _locationError ?? 'Location unavailable',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initLocation,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(int index) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_tabIcons[index], size: 56, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(
            'No ${_tabLabels[index].toLowerCase()} found nearby.',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _fetchTab(index),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceTile(_NearbyPlace place) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    place.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    place.distanceLabel,
                    style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (place.openingHours != null && place.openingHours!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time_outlined,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      place.openingHours!,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (place.phone != null && place.phone!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    place.phone!,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openInMaps(place),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Open in Maps'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                if (place.phone != null && place.phone!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _callPlace(place),
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(int index) {
    if (_locationLoading) return _buildSkeleton();
    if (_locationError != null) return _buildLocationError();
    if (_tabLoading[index]) return _buildSkeleton();

    final places = _results[index];
    if (places.isEmpty && _tabLoaded[index]) {
      return _buildEmptyState(index);
    }
    if (places.isEmpty) {
      return _buildSkeleton();
    }

    return RefreshIndicator(
      onRefresh: () => _fetchTab(index),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: places.length,
        itemBuilder: (_, i) => _buildPlaceTile(places[i]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        title: const Text('Nearby Services',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: BackButton(
          color: Colors.white,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: List.generate(
            3,
            (i) => Tab(
              icon: Icon(_tabIcons[i], size: 20),
              text: _tabLabels[i],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(3, _buildTabContent),
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
  final String? openingHours;
  final double? distanceMeters;

  const _NearbyPlace({
    required this.name,
    required this.lat,
    required this.lng,
    this.phone,
    this.openingHours,
    this.distanceMeters,
  });

  String get distanceLabel {
    final d = distanceMeters;
    if (d == null) return '';
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  factory _NearbyPlace.fromJson(
      Map<String, dynamic> json, Position userPosition) {
    final lat = (json['latitude'] ?? json['lat']) as num? ?? 0;
    final lng = (json['longitude'] ?? json['lng']) as num? ?? 0;

    final distanceMeters = _haversineDistance(
      userPosition.latitude,
      userPosition.longitude,
      lat.toDouble(),
      lng.toDouble(),
    );

    return _NearbyPlace(
      name: json['name']?.toString() ?? 'Unknown',
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      phone: json['phone']?.toString(),
      openingHours: json['opening_hours']?.toString() ??
          json['openingHours']?.toString(),
      distanceMeters: distanceMeters,
    );
  }

  static double _haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in metres
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
