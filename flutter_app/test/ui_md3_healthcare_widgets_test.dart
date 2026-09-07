import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/shared/widgets/ai_insight_teaser.dart';
import 'package:vitapulse_ai/shared/widgets/dynamic_greeting.dart';
import 'package:vitapulse_ai/shared/widgets/health_metric_card.dart';
import 'package:vitapulse_ai/shared/widgets/premium_surface.dart';
import 'package:vitapulse_ai/shared/widgets/responsive_layout.dart';
import 'package:vitapulse_ai/shared/widgets/section_header.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child, {Size size = const Size(390, 844)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: AppThemeBuilder.light(const AppThemeSettings()),
      darkTheme: AppThemeBuilder.dark(const AppThemeSettings()),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  test('DynamicGreeting phrase/icon by hour', () {
    expect(DynamicGreeting.phrase(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(DynamicGreeting.phrase(DateTime(2026, 1, 1, 14)), 'Good afternoon');
    expect(DynamicGreeting.phrase(DateTime(2026, 1, 1, 20)), 'Good evening');
    expect(DynamicGreeting.firstName('Alex Rivera'), 'Alex');
  });

  testWidgets('DynamicGreetingText renders accessible greeting', (tester) async {
    await tester.pumpWidget(
      _wrap(DynamicGreetingText(
        userName: 'Jordan Lee',
        now: DateTime(2026, 1, 1, 9),
      )),
    );
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Jordan'), findsOneWidget);
    expect(find.textContaining('👋'), findsNothing);
  });

  testWidgets('HealthMetricCard shows value and shimmer loading', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HealthMetricCard(
          icon: Icons.favorite,
          color: Colors.red,
          label: 'Heart Rate',
          value: '72 bpm',
          onTap: () {},
        ),
      ),
    );
    expect(find.text('72 bpm'), findsOneWidget);
    expect(find.text('Heart Rate'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        HealthMetricCard(
          icon: Icons.favorite,
          color: Colors.red,
          label: 'Heart Rate',
          value: '72 bpm',
          loading: true,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('72 bpm'), findsNothing);
  });

  testWidgets('AiInsightTeaser invokes callback', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(AiInsightTeaser(onOpen: () => opened = true)),
    );
    expect(find.text('AI health insights'), findsOneWidget);
    await tester.tap(find.byType(AiInsightTeaser));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('SoftSurface and SectionHeader render', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            SoftSurface(child: const Text('surface')),
            SectionHeader(
              icon: Icons.bolt,
              title: 'Quick Access',
              color: Colors.teal,
              subtitle: 'Tools',
            ),
          ],
        ),
      ),
    );
    expect(find.text('surface'), findsOneWidget);
    expect(find.text('Quick Access'), findsOneWidget);
  });

  testWidgets('ResponsiveLayout columns phone/tablet/expanded', (tester) async {
    late int phone;
    late int tablet;
    late int expanded;
    await tester.pumpWidget(
      _wrap(
        Builder(builder: (ctx) {
          phone = ResponsiveLayout.featureColumns(ctx);
          return const SizedBox.shrink();
        }),
        size: const Size(390, 844),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        Builder(builder: (ctx) {
          tablet = ResponsiveLayout.featureColumns(ctx);
          return const SizedBox.shrink();
        }),
        size: const Size(800, 1024),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        Builder(builder: (ctx) {
          expanded = ResponsiveLayout.featureColumns(ctx);
          return const SizedBox.shrink();
        }),
        size: const Size(1100, 1024),
      ),
    );
    expect(phone, 2);
    expect(tablet, 3);
    expect(expanded, 4);
  });

  testWidgets('Theme builds light and dark without error', (tester) async {
    final light = AppThemeBuilder.light(const AppThemeSettings());
    final dark = AppThemeBuilder.dark(const AppThemeSettings());
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.cardTheme.elevation, 1);
    await tester.pumpWidget(
      MaterialApp(
        theme: light,
        darkTheme: dark,
        themeMode: ThemeMode.dark,
        home: const Scaffold(body: Text('ok')),
      ),
    );
    expect(find.text('ok'), findsOneWidget);
  });
}
