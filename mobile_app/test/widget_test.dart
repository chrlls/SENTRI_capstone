import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/main.dart';

void main() {
  testWidgets('SentriApp launches on the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SentriApp());

    expect(find.text('SENTRI Login'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });
}
