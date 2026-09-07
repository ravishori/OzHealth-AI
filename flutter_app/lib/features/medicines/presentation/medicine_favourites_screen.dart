import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/features/medicines/data/medicine_api.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/theme/design_tokens/app_radius.dart';

typedef MedicineFavouritesLoader = Future<List<Map<String, dynamic>>> Function();

/// HN-MED-009 — user-scoped medicine favourites (bookmark list only).
///
/// Not a medication schedule, prescription, TGA/PBS check, or clinical
/// recommendation.
class MedicineFavouritesScreen extends StatefulWidget {
  final MedicineFavouritesLoader? loadFavourites;

  const MedicineFavouritesScreen({
    super.key,
    this.loadFavourites,
  });

  @override
  State<MedicineFavouritesScreen> createState() =>
      _MedicineFavouritesScreenState();
}

class _MedicineFavouritesScreenState extends State<MedicineFavouritesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final loader = widget.loadFavourites ?? MedicineApi.listFavourites;
      final items = await loader();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getMessage(e);
        _loading = false;
      });
    }
  }

  void _openDetail(Map<String, dynamic> medicine) {
    final rawId = medicine['id'];
    final id = rawId?.toString() ?? '';
    if (id.isEmpty || int.tryParse(id) == null) return;
    context.push('/home/medicines/$id', extra: medicine);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favourite Medicines'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home/medicines');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          key: Key('medicine_favourites_loading'),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return EmptyState(
        key: const Key('medicine_favourites_empty'),
        icon: Icons.favorite_border,
        title: 'No favourite medicines yet',
        subtitle:
            'Bookmark medicines from search for quick access. '
            'Favourites are personal bookmarks — not prescriptions or recommendations.',
        actionLabel: 'Browse medicines',
        onAction: () => context.go('/home/medicines'),
      );
    }

    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('medicine_favourites_list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Your saved medicine bookmarks. Not a medication list or prescription.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            );
          }
          final medicine = _items[index - 1];
          final name = medicine['name']?.toString() ?? 'Medicine';
          final generic = medicine['generic_name']?.toString() ?? '';
          final strength = medicine['strength']?.toString() ?? '';
          final subtitle = [
            if (generic.isNotEmpty) generic,
            if (strength.isNotEmpty) strength,
          ].join(' · ');
          return Material(
            color: cs.surfaceContainerLowest,
            borderRadius: AppRadius.brMd,
            child: ListTile(
              key: Key('medicine_favourite_item_${medicine['id']}'),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.brMd),
              leading: Icon(Icons.favorite, color: cs.error),
              title: Text(name),
              subtitle: subtitle.isEmpty ? null : Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDetail(medicine),
            ),
          );
        },
      ),
    );
  }
}
