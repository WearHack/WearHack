/// Mantiene de acuerdo a la app (Dart) y a `tools/captura/importar_lote.py`.
///
/// Son dos programas en dos lenguajes que tienen que leer exactamente el mismo
/// formato: el JSON de cada toma, el manifiesto y el hash global. Si uno cambia y
/// el otro no, un lote real fallaria al importarse, en el momento menos oportuno.
///
/// Por eso los dos leen los mismos archivos de referencia, que **genera la app**:
///
///   tools/captura/ejemplos/metadatos_ejemplo.json
///   tools/captura/ejemplos/manifiesto_ejemplo.json
///
/// Este test comprueba que lo que la app produce hoy es identico a esos archivos,
/// y `tools/captura/test_importar_lote.py` comprueba que el script los acepta. Si
/// el formato cambia a proposito, se regeneran con:
///
///   ACTUALIZAR_GOLDEN=1 flutter test test/paridad_con_python_test.dart
///
/// y se revisa el cambio en el diff. Los archivos son sinteticos: ningun dato de
/// una persona.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/features/captura_pruebas/lote.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';

import 'helpers/captura_helpers.dart';

const String _carpeta = '../tools/captura/ejemplos';

MetadatosToma _muestra() => MetadatosToma(
  id: idDe(),
  fechaHora: DateTime.utc(2026, 10, 15, 20, 42, 7),
  celular: datosDelCelular(),
  parametrosCamara: const ParametrosDeCamara(exposicion: 0.5, iso: 400),
  rostroBbox: const <num>[100, 100, 250, 270],
  anchoRostroPx: 150,
  perfilFoto: 'Display P3',
  perfilRecorte: 'sRGB (convertido por la app)',
  archivoFoto: 'P3_LEDC_D2_R1_G_foto.jpg',
  archivoRecorte: 'P3_LEDC_D2_R1_G_recorte.png',
  sha256Foto: 'a' * 64,
  sha256Recorte: 'b' * 64,
);

Manifiesto _manifiestoDeMuestra() {
  final List<EntradaManifiesto> entradas = <EntradaManifiesto>[
    EntradaManifiesto(
      ruta: 'P3_LEDC_D2_R1_G.json',
      sha256: 'c' * 64,
      bytes: 1200,
    ),
    EntradaManifiesto(
      ruta: 'P3_LEDC_D2_R1_G_foto.jpg',
      sha256: 'a' * 64,
      bytes: 3000000,
    ),
    EntradaManifiesto(
      ruta: 'P3_LEDC_D2_R1_G_recorte.png',
      sha256: 'b' * 64,
      bytes: 250000,
    ),
  ];
  return Manifiesto(
    entradas: entradas,
    hashGlobal: calcularHashGlobal(entradas),
  );
}

String _texto(Object? json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

void _comprobar(String nombre, Object? generado) {
  final File archivo = File('$_carpeta/$nombre');
  if (Platform.environment['ACTUALIZAR_GOLDEN'] == '1') {
    archivo.parent.createSync(recursive: true);
    archivo.writeAsStringSync(_texto(generado));
  }
  expect(
    archivo.existsSync(),
    isTrue,
    reason: 'Falta ${archivo.path}. Generalo con ACTUALIZAR_GOLDEN=1.',
  );
  expect(
    jsonDecode(archivo.readAsStringSync()),
    equals(jsonDecode(jsonEncode(generado))),
    reason:
        '${archivo.path} ya no coincide con lo que produce la app. Si el '
        'formato cambio a proposito, regeneralo con ACTUALIZAR_GOLDEN=1 y '
        'actualiza importar_lote.py.',
  );
}

void main() {
  test('el JSON de una toma coincide con el archivo de referencia', () {
    // La fecha se formatea con el huso horario de la maquina. Aqui se fija el
    // desfase para que el resultado no dependa de donde corra el test; el
    // formato con desfase ya tiene su propio test.
    final Map<String, Object?> json = _muestra().toJson()
      ..['fecha_hora'] = formatearFechaConOffset(
        DateTime.utc(2026, 10, 15, 20, 42, 7),
        desfase: const Duration(hours: -5),
      );
    _comprobar('metadatos_ejemplo.json', json);
  });

  test('el manifiesto coincide con el archivo de referencia', () {
    _comprobar('manifiesto_ejemplo.json', _manifiestoDeMuestra().toJson());
  });

  test('el archivo de referencia de metadatos cumple el esquema de la app', () {
    final Object? json = jsonDecode(
      File('$_carpeta/metadatos_ejemplo.json').readAsStringSync(),
    );

    expect(validarMetadatos(json), isEmpty);
  });

  test('el hash global de referencia es el mismo que calcula el script', () {
    // El mismo vector y el mismo resultado estan en test_importar_lote.py. Los
    // nombres mezclan mayuscula y minuscula a proposito: el orden es ordinal.
    final String hash = calcularHashGlobal(<EntradaManifiesto>[
      EntradaManifiesto(ruta: 'B.jpg', sha256: '1' * 64, bytes: 1),
      EntradaManifiesto(ruta: 'a.jpg', sha256: '2' * 64, bytes: 1),
      EntradaManifiesto(
        ruta: 'P3_LEDC_D2_R1_G.json',
        sha256: 'c' * 64,
        bytes: 1,
      ),
    ]);

    expect(
      hash,
      '0e11c978905cd7059f7caa36b1469fb8d1a1bad5394a122c585eba3033c5bd42',
    );
  });

  test('las 15 luces y repeticiones del script son las de la app', () {
    // importar_lote.py repite estos codigos; si la app agrega uno, hay que
    // agregarlo alla.
    expect(Luz.values.map((Luz l) => l.codigo), <String>[
      'VEN',
      'LEDC',
      'LEDF',
      'MIX',
      'BAJ',
    ]);
    expect(CodigoCelular.values.map((CodigoCelular c) => c.codigo), <String>[
      'D1',
      'D2',
      'D3',
    ]);
    expect(Repeticion.values.map((Repeticion r) => r.codigo), <String>[
      'R1',
      'R2',
      'R3',
    ]);
  });
}
