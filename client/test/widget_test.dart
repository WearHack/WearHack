import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/main.dart';
import 'package:wearhack/mock/repositorio_falso.dart';

void main() {
  testWidgets('la aplicacion arranca en el closet', (
    WidgetTester tester,
  ) async {
    final RepositorioFalso datos = RepositorioFalso(latencia: Duration.zero);
    await tester.pumpWidget(AplicacionWearHack(closet: datos, outfits: datos));
    await tester.pumpAndSettle();

    expect(find.text('Clóset'), findsWidgets);
    expect(find.text('Jean'), findsOneWidget);
  });

  testWidgets('el diagnostico sigue mostrando la pantalla de esqueleto', (
    WidgetTester tester,
  ) async {
    final RepositorioFalso datos = RepositorioFalso(latencia: Duration.zero);
    await tester.pumpWidget(AplicacionWearHack(closet: datos, outfits: datos));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Diagnóstico'));
    await tester.pumpAndSettle();

    expect(find.text('Esqueleto'), findsOneWidget);
    expect(find.textContaining('clasificacion on-device'), findsOneWidget);
  });
}
