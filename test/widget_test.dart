

import 'package:flutter_test/flutter_test.dart';

import 'package:farm_go_app/main.dart';

void main() {
  testWidgets('FarmGo App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FarmGoApp());

    // Verify that the title text is present
    expect(find.text('FarmGo'), findsOneWidget);

    // Verify that the hero section text is present
    expect(find.text('Securing Our Farms, Digitally.'), findsOneWidget);
  });
}
