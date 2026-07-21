import 'package:flutter_test/flutter_test.dart';

import 'package:client/main.dart';

void main() {
  testWidgets('Shows France, timer and toggles connection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('BRATANVPN'), findsOneWidget);
    expect(find.text('Подключиться'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('Франция'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);

    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pump();

    expect(find.text('Подключено'), findsOneWidget);
    expect(find.text('Подключиться'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:00:02'), findsOneWidget);
  });
}
