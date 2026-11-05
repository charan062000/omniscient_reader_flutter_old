import 'package:flutter_test/flutter_test.dart';
import 'package:omniscient_reader/main.dart';

void main() {
  testWidgets('Omniscient Reader starts on the library screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OmniscientReaderApp());

    expect(find.text('OMNISCIENT'), findsOneWidget);
    expect(find.text('My library'), findsOneWidget);
  });
}
