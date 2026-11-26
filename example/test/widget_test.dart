import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:uae_pass_kit_example/main.dart';

void main() {
  testWidgets('shows the app name and the UAE PASS sign-in button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const UaePassKitExampleApp());

    expect(find.text('UAE Pass Kit'), findsWidgets);
    expect(
      find.widgetWithText(FilledButton, 'Sign in with UAE PASS'),
      findsOneWidget,
    );
  });
}
