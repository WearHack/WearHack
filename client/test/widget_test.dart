import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/main.dart';

void main() {
  testWidgets('la aplicacion arranca y pinta la pantalla de esqueleto', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AplicacionWearHack());

    expect(find.text('Esqueleto'), findsOneWidget);
    expect(find.textContaining('clasificacion on-device'), findsOneWidget);
  });
}
