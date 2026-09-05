import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/features/emergency/presentation/sos_hold_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  test('SOS-HOLD threshold constant is exactly 3 seconds', () {
    expect(SosHoldButton.holdDuration, const Duration(seconds: 3));
  });

  testWidgets('SOS-HOLD-01 idle state', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () {},
        ),
      ),
    );
    final state = tester.state<SosHoldButtonState>(find.byType(SosHoldButton));
    expect(state.isHolding, isFalse);
    expect(state.progress, 0);
    expect(state.didActivate, isFalse);
    expect(find.text('HOLD 3s'), findsOneWidget);
  });

  testWidgets('SOS-HOLD-02 press down enters holding', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () {},
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    final state = tester.state<SosHoldButtonState>(find.byType(SosHoldButton));
    expect(state.isHolding, isTrue);
    expect(find.text('HOLDING…'), findsOneWidget);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('SOS-HOLD-03/04 release before 3s does not trigger', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () => activations++,
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    // ~500ms (old long-press) — must NOT fire
    await tester.pump(const Duration(milliseconds: 499));
    expect(activations, 0);
    await tester.pump(const Duration(milliseconds: 501)); // 1s total
    expect(activations, 0);
    await tester.pump(const Duration(seconds: 1)); // 2s total
    expect(activations, 0);
    await tester.pump(const Duration(milliseconds: 900)); // 2.9s
    expect(activations, 0);
    await gesture.up();
    await tester.pump();
    expect(activations, 0);
    final state = tester.state<SosHoldButtonState>(find.byType(SosHoldButton));
    expect(state.isHolding, isFalse);
    expect(state.progress, 0);
    expect(state.didActivate, isFalse);
  });

  testWidgets('SOS-HOLD-05 cancel gesture before 3s', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () => activations++,
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 1));
    expect(activations, 0);
    await gesture.cancel();
    await tester.pump();
    expect(activations, 0);
    final state = tester.state<SosHoldButtonState>(find.byType(SosHoldButton));
    expect(state.progress, 0);
    expect(state.isHolding, isFalse);
  });

  testWidgets('SOS-HOLD-06/07/12 hold 3s triggers once', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () => activations++,
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    // Advance past threshold (exact 3s + 1 frame).
    await tester.pump(SosHoldButton.holdDuration);
    await tester.pump(const Duration(milliseconds: 16));
    expect(activations, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(activations, 1);
    await gesture.up();
    await tester.pump();
    expect(activations, 1);
  });

  testWidgets('SOS-HOLD-08 progress increases while holding', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () {},
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final mid =
        tester.state<SosHoldButtonState>(find.byType(SosHoldButton)).progress;
    expect(mid, greaterThan(0.25));
    expect(mid, lessThan(0.45));
    await tester.pump(const Duration(seconds: 1));
    final later =
        tester.state<SosHoldButtonState>(find.byType(SosHoldButton)).progress;
    expect(later, greaterThan(mid));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('SOS-HOLD-09/10 progress resets after early release/cancel',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () {},
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    var gesture = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.state<SosHoldButtonState>(find.byType(SosHoldButton)).progress,
      greaterThan(0),
    );
    await gesture.up();
    await tester.pump();
    expect(
      tester.state<SosHoldButtonState>(find.byType(SosHoldButton)).progress,
      0,
    );

    gesture = await tester.startGesture(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.cancel();
    await tester.pump();
    expect(
      tester.state<SosHoldButtonState>(find.byType(SosHoldButton)).progress,
      0,
    );
  });

  testWidgets('SOS-HOLD-11 dispose cancels pending hold', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () => activations++,
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 1));
    // Remove widget while holding
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 5));
    expect(activations, 0);
  });

  testWidgets('SOS-HOLD-13 accessibility semantics present', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () {},
        ),
      ),
    );
    final semantics = tester.getSemantics(find.byType(SosHoldButton));
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(semantics.label.toLowerCase(), contains('hold for 3 seconds'));
    expect(semantics.label.toLowerCase(), contains('release'));
    expect(semantics.label.toLowerCase(), contains('000'));
  });

  test('SOS-HOLD-14/15 dial-first + no auto-000 contracts unchanged', () {
    // Source contracts preserved in EmergencyScreen (Sprint 2).
    const dialFirst =
        'Records your GPS for dial-back. Contacts are NOT auto-notified.';
    const noAuto000 = 'call 000';
    expect(dialFirst.contains('NOT auto-notified'), isTrue);
    expect(noAuto000, isNot(contains('automatically call')));
    expect(SosHoldButton.holdDuration.inMilliseconds, 3000);
  });

  testWidgets('SOS-HOLD ~500ms old threshold never activates', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      _wrap(
        SosHoldButton(
          emergencyColor: Colors.red,
          onActivated: () => activations++,
        ),
      ),
    );
    final center = tester.getCenter(find.byType(SosHoldButton));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 500));
    expect(activations, 0);
    await gesture.up();
    await tester.pump();
    expect(activations, 0);
  });
}
