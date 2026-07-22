import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/main.dart';
import 'package:client/services/activation_api.dart';

class _FakeActivationApi extends ActivationApi {
  _FakeActivationApi({this.failWith});

  final ActivationException? failWith;
  int calls = 0;

  @override
  Future<ActivationSuccess> activate({
    required String accessKey,
    required String deviceId,
    required String vpnPublicKey,
  }) async {
    calls += 1;
    if (failWith != null) {
      throw failWith!;
    }
    return const ActivationSuccess(vpnIp: '10.8.0.2');
  }
}

void main() {
  testWidgets('First connect activates via API then connects', (
    WidgetTester tester,
  ) async {
    final api = _FakeActivationApi();
    await tester.pumpWidget(MyApp(activationApi: api));

    expect(find.text('Подключиться'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(find.text('Введите ключ доступа'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(find.text('Подключено'), findsOneWidget);
    expect(find.text('Введите ключ доступа'), findsNothing);
  });

  testWidgets('Shows API error and stays on dialog', (WidgetTester tester) async {
    final api = _FakeActivationApi(
      failWith: ActivationException('Ключ не найден.'),
    );
    await tester.pumpWidget(MyApp(activationApi: api));

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BAD-KEY');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    expect(find.text('Ключ не найден.'), findsOneWidget);
    expect(find.text('Введите ключ доступа'), findsOneWidget);
    expect(find.text('Подключено'), findsNothing);
  });

  testWidgets('After activation connect works without dialog', (
    WidgetTester tester,
  ) async {
    final api = _FakeActivationApi();
    await tester.pumpWidget(MyApp(activationApi: api));

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'BRATAN-TESTKEY01');
    await tester.tap(find.widgetWithText(TextButton, 'Подключиться'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();
    expect(find.text('Подключиться'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pumpAndSettle();

    expect(find.text('Введите ключ доступа'), findsNothing);
    expect(find.text('Подключено'), findsOneWidget);
    expect(api.calls, 1);
  });
}
