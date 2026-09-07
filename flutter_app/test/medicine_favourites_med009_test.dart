import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vitapulse_ai/features/medicines/data/medicine_api.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_detail_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_favourites_screen.dart';
import 'package:vitapulse_ai/features/medicines/presentation/medicine_search_screen.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Map<String, dynamic> _sampleMedicine({int id = 42}) => {
      'id': id,
      'name': 'Amoxicillin 500 mg',
      'generic_name': 'Amoxicillin',
      'composition': 'Amoxicillin 500 mg',
      'tga_registered': true,
      'field_sources': {
        'composition': 'database',
        'standard_dosage': 'unavailable',
      },
      'provenance': {
        'labels': {
          'database': 'From medicine database',
          'unavailable': 'Information not available',
          'ai_explanation': 'AI-generated explanation',
        },
      },
    };

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: child,
  );
}

void main() {
  final detailSrc = File(
          'lib/features/medicines/presentation/medicine_detail_screen.dart')
      .readAsStringSync();
  final favSrc = File(
          'lib/features/medicines/presentation/medicine_favourites_screen.dart')
      .readAsStringSync();
  final apiSrc =
      File('lib/features/medicines/data/medicine_api.dart').readAsStringSync();

  testWidgets('MED-FAV-FE-01 detail displays unfavourited state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicineDetailScreen(
          medicineId: '42',
          loadMedicine: (_) async => _sampleMedicine(),
          loadExplanation: (_) async => null,
          loadFavouriteStatus: (_) async => false,
          setFavourite: (id, {required favourite}) async => favourite,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medicine_favourite_toggle')), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byTooltip('Add to favourites'), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-02 favourite action changes state', (tester) async {
    var isFav = false;
    await tester.pumpWidget(
      _wrap(
        MedicineDetailScreen(
          medicineId: '42',
          loadMedicine: (_) async => _sampleMedicine(),
          loadExplanation: (_) async => null,
          loadFavouriteStatus: (_) async => isFav,
          setFavourite: (id, {required favourite}) async {
            isFav = favourite;
            return favourite;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine_favourite_toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byTooltip('Remove from favourites'), findsOneWidget);
    expect(find.textContaining('Saved to favourites'), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-03 unfavourite action changes state', (tester) async {
    var isFav = true;
    await tester.pumpWidget(
      _wrap(
        MedicineDetailScreen(
          medicineId: '42',
          loadMedicine: (_) async => _sampleMedicine(),
          loadExplanation: (_) async => null,
          loadFavouriteStatus: (_) async => isFav,
          setFavourite: (id, {required favourite}) async {
            isFav = favourite;
            return favourite;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    await tester.tap(find.byKey(const Key('medicine_favourite_toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.textContaining('Removed from favourites'), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-04 loading prevents duplicate rapid actions',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(
        MedicineDetailScreen(
          medicineId: '42',
          loadMedicine: (_) async => _sampleMedicine(),
          loadExplanation: (_) async => null,
          loadFavouriteStatus: (_) async => false,
          setFavourite: (id, {required favourite}) async {
            calls += 1;
            await Future<void>.delayed(const Duration(milliseconds: 400));
            return favourite;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine_favourite_toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('medicine_favourite_toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('medicine_favourite_toggle')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('MED-FAV-FE-05 favourite failure shows safe user feedback',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicineDetailScreen(
          medicineId: '42',
          loadMedicine: (_) async => _sampleMedicine(),
          loadExplanation: (_) async => null,
          loadFavouriteStatus: (_) async => false,
          setFavourite: (id, {required favourite}) async {
            throw Exception('network failed');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine_favourite_toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-06 empty favourites state renders', (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicineFavouritesScreen(
          loadFavourites: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medicine_favourites_empty')), findsOneWidget);
    expect(find.text('No favourite medicines yet'), findsOneWidget);
    expect(find.text('Browse medicines'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-07 favourite list renders returned medicines',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicineFavouritesScreen(
          loadFavourites: () async => [
            {
              'id': 42,
              'name': 'Amoxicillin 500 mg',
              'generic_name': 'Amoxicillin',
              'strength': '500 mg',
            },
            {
              'id': 7,
              'name': 'Paracetamol 500 mg',
              'generic_name': 'Paracetamol',
              'strength': '500 mg',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('medicine_favourites_list')), findsOneWidget);
    expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
    expect(find.text('Paracetamol 500 mg'), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-08 selecting favourite navigates to medicine detail',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/favourites',
      routes: [
        GoRoute(
          path: '/favourites',
          builder: (_, __) => MedicineFavouritesScreen(
            loadFavourites: () async => [
              {
                'id': 42,
                'name': 'Amoxicillin 500 mg',
                'generic_name': 'Amoxicillin',
              },
            ],
          ),
        ),
        GoRoute(
          path: '/home/medicines/:id',
          builder: (_, state) => Scaffold(
            body: Text('detail-${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppThemeBuilder.light(const AppThemeSettings()),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('medicine_favourite_item_42')));
    await tester.pumpAndSettle();
    expect(find.text('detail-42'), findsOneWidget);
  });

  testWidgets('MED-FAV-FE-09 existing medicine detail/search preserved',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        MedicineDetailScreen(
          medicineId: '42',
          loadMedicine: (_) async => _sampleMedicine(),
          loadExplanation: (_) async => null,
          loadFavouriteStatus: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Amoxicillin 500 mg'), findsWidgets);
    expect(find.textContaining('From medicine database'), findsWidgets);

    await tester.pumpWidget(
      _wrap(const MedicineSearchScreen()),
    );
    await tester.pump();
    expect(find.text('Medicine Information'), findsOneWidget);
    expect(find.byTooltip('Favourite medicines'), findsOneWidget);
  });

  test('MED-FAV-FE API surface includes favourite methods', () {
    expect(MedicineApi.getFavouriteStatus, isA<Function>());
    expect(MedicineApi.addFavourite, isA<Function>());
    expect(MedicineApi.removeFavourite, isA<Function>());
    expect(MedicineApi.listFavourites, isA<Function>());
    expect(apiSrc.contains('/medicines/favourites'), isTrue);
    expect(apiSrc.contains('/favourite'), isTrue);
  });

  test('MED-FAV-FE copy distinguishes favourite from prescription', () {
    expect(detailSrc.toLowerCase().contains('not a prescription'), isTrue);
    expect(favSrc.contains('No favourite medicines yet'), isTrue);
    expect(
      favSrc.contains('Not a medication list or prescription') ||
          favSrc.toLowerCase().contains('not prescriptions'),
      isTrue,
    );
  });

  test('MED-FAV-FE-10 favourites are auth-scoped; no client user_id override', () {
    // Client must not send user_id/owner_id; server derives principal from JWT.
    expect(apiSrc.contains("'user_id'"), isFalse);
    expect(apiSrc.contains("'owner_id'"), isFalse);
    expect(apiSrc.contains('listFavourites'), isTrue);
    expect(apiSrc.contains("ApiClient.get('/medicines/favourites')"), isTrue);
    // Favourites screen loads from API each visit (no cross-user local stash).
    expect(favSrc.contains('MedicineApi.listFavourites'), isTrue);
  });
}
