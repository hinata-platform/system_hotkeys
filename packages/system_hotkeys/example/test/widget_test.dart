import 'package:flutter_test/flutter_test.dart';
import 'package:system_hotkeys_example/main.dart';

void main() {
  testWidgets('lists the combinations it binds', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('toggle'), findsOneWidget);
    expect(find.text('focus'), findsOneWidget);
  });
}
