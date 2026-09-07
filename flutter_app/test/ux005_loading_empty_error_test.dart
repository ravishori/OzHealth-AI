import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitapulse_ai/core/utils/error_handler.dart';
import 'package:vitapulse_ai/shared/widgets/empty_state.dart';
import 'package:vitapulse_ai/shared/widgets/error_state.dart';
import 'package:vitapulse_ai/theme/app_theme_builder.dart';
import 'package:vitapulse_ai/theme/theme_manager.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppThemeBuilder.light(const AppThemeSettings()),
    home: Scaffold(body: child),
  );
}

DioException _dio({
  required int status,
  dynamic data,
}) {
  return DioException(
    requestOptions: RequestOptions(path: '/api/secret'),
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: RequestOptions(path: '/api/secret'),
      statusCode: status,
      data: data,
    ),
  );
}

void main() {
  final familySrc =
      File('lib/features/family/presentation/family_screen.dart')
          .readAsStringSync();
  final recordsSrc =
      File('lib/features/records/presentation/records_screen.dart')
          .readAsStringSync();
  final remindersSrc =
      File('lib/features/reminders/presentation/reminders_screen.dart')
          .readAsStringSync();
  final errorHandlerSrc =
      File('lib/core/utils/error_handler.dart').readAsStringSync();
  final errorStateSrc =
      File('lib/shared/widgets/error_state.dart').readAsStringSync();

  test('UX-005-FL-01 loading keys / soft-refresh preserve content', () {
    expect(familySrc.contains("Key('family-loading')"), isTrue);
    expect(familySrc.contains('soft: true'), isTrue);
    expect(
      familySrc.contains('if (!soft || _members.isEmpty) _loading = true'),
      isTrue,
    );

    expect(recordsSrc.contains("Key('records-loading')"), isTrue);
    expect(recordsSrc.contains('hasCache'), isTrue);

    expect(remindersSrc.contains("Key('reminders-loading')"), isTrue);
    expect(
      remindersSrc
          .contains('if (!soft || _reminders.isEmpty) _loading = true'),
      isTrue,
    );
  });

  test('UX-005-FL-02 empty states use EmptyState widget', () {
    expect(familySrc.contains('EmptyState'), isTrue);
    expect(familySrc.contains("Key('family-empty')"), isTrue);

    expect(recordsSrc.contains('EmptyState'), isTrue);
    expect(recordsSrc.contains("Key('records-empty')"), isTrue);

    expect(remindersSrc.contains('EmptyState'), isTrue);
    expect(remindersSrc.contains("Key('reminders-empty')"), isTrue);
  });

  test('UX-005-FL-03 error states use ErrorState and ErrorHandler', () {
    expect(familySrc.contains('ErrorState'), isTrue);
    expect(familySrc.contains('ErrorHandler.getMessage'), isTrue);
    expect(familySrc.contains('_error != null && _members.isEmpty'), isTrue);

    expect(recordsSrc.contains('ErrorState'), isTrue);
    expect(recordsSrc.contains('ErrorHandler.getMessage'), isTrue);
    expect(recordsSrc.contains('_errorsByTab'), isTrue);

    expect(remindersSrc.contains('ErrorState'), isTrue);
    expect(remindersSrc.contains('ErrorHandler.getMessage'), isTrue);
    expect(
      remindersSrc.contains('_error.isNotEmpty && _reminders.isEmpty'),
      isTrue,
    );
    expect(remindersSrc.contains("'Failed to load reminders.'"), isFalse);
  });

  testWidgets('UX-005-FL-04 ErrorState retry button invokes callback',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(
        ErrorState(
          message: 'Unable to load data right now.',
          onRetry: () => retries++,
        ),
      ),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('error-state-retry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('error-state-retry')));
    await tester.pump();
    expect(retries, 1);

    expect(familySrc.contains('onRetry:'), isTrue);
    expect(recordsSrc.contains('onRetry:'), isTrue);
    expect(remindersSrc.contains('onRetry:'), isTrue);
  });

  test('UX-005-FL-05 duplicate delete/mutate actions are gated', () {
    expect(familySrc.contains('if (_deleting) return;'), isTrue);
    expect(recordsSrc.contains('if (_deleting) return;'), isTrue);
    expect(remindersSrc.contains('if (_mutating) return;'), isTrue);
  });

  test('UX-005-FL-06 loading cleared on success paths', () {
    expect(familySrc.contains('_loading = false'), isTrue);
    expect(recordsSrc.contains('_loadingTabs.remove'), isTrue);
    expect(remindersSrc.contains('_loading = false'), isTrue);
  });

  test('UX-005-FL-07 loading cleared on failure paths', () {
    final familyCatch = familySrc.split('catch (e)').skip(1).first;
    expect(familyCatch.contains('_loading = false'), isTrue);

    final remindersCatch = remindersSrc.split('catch (e)').firstWhere(
          (chunk) => chunk.contains('_error = message'),
        );
    expect(remindersCatch.contains('_loading = false'), isTrue);

    expect(recordsSrc.contains('finally'), isTrue);
    expect(recordsSrc.contains('_loadingTabs.remove'), isTrue);
  });

  test('UX-005-FL-08 prior data retained on refresh failure', () {
    expect(familySrc.contains('if (_members.isEmpty)'), isTrue);
    expect(familySrc.contains('Distinguish error from empty'), isTrue);
    expect(recordsSrc.contains('stale-while-error'), isTrue);
    expect(remindersSrc.contains('soft-refresh failure'), isTrue);
  });

  test('UX-005-FL-09 ErrorHandler sanitizes unsafe backend messages', () {
    expect(errorHandlerSrc.contains('_sanitizeUserMessage'), isTrue);

    expect(
      ErrorHandler.getMessage(
        _dio(status: 503, data: {'detail': 'upstream unavailable'}),
      ),
      'Something went wrong. Please try again later.',
    );

    expect(
      ErrorHandler.getMessage(
        _dio(
          status: 400,
          data: {
            'detail':
                'Traceback (most recent call last):\n  File "/app/main.py"',
          },
        ),
      ),
      isNot(contains('Traceback')),
    );

    expect(
      ErrorHandler.getMessage(
        _dio(
          status: 400,
          data: {'detail': 'SELECT * FROM users WHERE token=Bearer abc'},
        ),
      ),
      isNot(contains('SELECT')),
    );

    expect(
      ErrorHandler.getMessage(
        _dio(
          status: 400,
          data: {'message': 'See https://api.internal/health for details'},
        ),
      ),
      isNot(contains('https://')),
    );

    expect(
      ErrorHandler.getMessage(Exception('socket hang up /api/family/')),
      'Something went wrong. Please try again.',
    );
  });

  testWidgets('UX-005-FL-09b ErrorState does not render raw exception text',
      (tester) async {
    const unsafe =
        'DioException [bad response]: https://api.example/records SQLAlchemy';
    await tester.pumpWidget(
      _wrap(
        ErrorState(
          message: ErrorHandler.getMessage(Exception(unsafe)),
        ),
      ),
    );
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('https://'), findsNothing);
    expect(find.textContaining('SQLAlchemy'), findsNothing);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('UX-005-FL-10 EmptyState and ErrorState are visually distinct',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyState(
          icon: Icons.people_outline,
          title: 'No family members yet',
          subtitle: 'Add members to manage their health',
        ),
      ),
    );
    expect(find.text('No family members yet'), findsOneWidget);
    expect(find.byKey(const Key('error-state-retry')), findsNothing);

    await tester.pumpWidget(
      _wrap(
        ErrorState(
          message: 'Unable to load data right now.',
          onRetry: () {},
        ),
      ),
    );
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('No family members yet'), findsNothing);
    expect(find.byKey(const Key('error-state-retry')), findsOneWidget);

    expect(errorStateSrc.contains('empty datasets'), isTrue);
    expect(familySrc.contains('Distinguish error from empty'), isTrue);
  });
}
