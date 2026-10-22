/// Vocabulario de la captura de pruebas y esquema de metadatos.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';

import 'helpers/captura_helpers.dart';

MetadatosToma _muestra({
  IdToma? id,
  ParametrosDeCamara parametros = const ParametrosDeCamara(),
  bool? espejo,
}) {
  final IdToma idToma = id ?? idDe();
  return MetadatosToma(
    id: idToma,
    fechaHora: DateTime.utc(2026, 10, 15, 20, 42, 7),
    celular: datosDelCelular(codigo: idToma.celular),
    parametrosCamara: parametros,
    espejo: espejo,
    rostroBbox: const <num>[100, 100, 250, 270],
    anchoRostroPx: 150,
    perfilFoto: 'Display P3',
    perfilRecorte: 'sRGB (convertido por la app)',
    archivoFoto: '${idToma.nombreBase}_foto.jpg',
    archivoRecorte: '${idToma.nombreBase}_recorte.png',
    sha256Foto: 'a' * 64,
    sha256Recorte: 'b' * 64,
  );
}

Map<String, Object?> _json([MetadatosToma? m]) =>
    jsonDecode(jsonEncode((m ?? _muestra()).toJson())) as Map<String, Object?>;

void main() {
  group('identificador de toma', () {
    test('el nombre sigue la convencion de la spec', () {
      expect(idDe().nombreBase, 'P3_LEDC_D2_R1_G');
      expect(idDe(repeticion: Repeticion.r2).nombreBase, 'P3_LEDC_D2_R2_N');
      expect(idDe(repeticion: Repeticion.r3).nombreBase, 'P3_LEDC_D2_R3_N');
    });

    test('solo R1 lleva tarjeta gris', () {
      expect(Repeticion.r1.llevaTarjetaGris, isTrue);
      expect(Repeticion.r2.llevaTarjetaGris, isFalse);
      expect(Repeticion.r3.llevaTarjetaGris, isFalse);
    });

    test('las 270 combinaciones del protocolo dan 270 nombres distintos y se leen de vuelta', () {
      final Set<String> nombres = <String>{};
      for (int persona = 1; persona <= 6; persona++) {
        for (final Luz luz in Luz.values) {
          for (final CodigoCelular cel in CodigoCelular.values) {
            for (final Repeticion rep in Repeticion.values) {
              final IdToma id = idDe(
                seudonimo: 'P$persona',
                luz: luz,
                celular: cel,
                repeticion: rep,
              );
              nombres.add(id.nombreBase);
              expect(IdToma.desdeNombreBase(id.nombreBase), id);
            }
          }
        }
      }
      expect(nombres, hasLength(6 * 5 * 3 * 3));
    });

    for (final String malo in <String>[
      'P3_LEDC_D2_R1_N', // R1 debe llevar G
      'P3_LEDC_D2_R2_G', // R2 debe llevar N
      'P7_LEDC_D2_R1_G',
      'P0_LEDC_D2_R1_G',
      'p3_LEDC_D2_R1_G',
      'P3_LEDX_D2_R1_G',
      'P3_LEDC_D4_R1_G',
      'P3_LEDC_D2_R4_N',
      'P3_LEDC_D2_R1',
      'P3_LEDC_D2_R1_G_extra',
      '',
    ]) {
      test('no se lee "$malo"', () {
        expect(IdToma.desdeNombreBase(malo), isNull);
      });
    }

    for (final String malo in <String>[
      'P0',
      'P7',
      'p1',
      ' P1',
      'P1\n',
      'P10',
      'Ana',
      '',
    ]) {
      test('el seudonimo "${malo.replaceAll('\n', r'\n')}" se rechaza', () {
        expect(() => Seudonimo(malo), throwsArgumentError);
      });
    }
  });

  group('fecha con desfase', () {
    test('formato de la spec', () {
      expect(
        formatearFechaConOffset(
          DateTime.utc(2026, 10, 15, 20, 42, 7),
          desfase: const Duration(hours: -5),
        ),
        '2026-10-15T15:42:07-05:00',
      );
    });

    test('desfase positivo con minutos', () {
      expect(
        formatearFechaConOffset(
          DateTime.utc(2026, 10, 15, 20, 42, 7),
          desfase: const Duration(hours: 5, minutes: 30),
        ),
        '2026-10-16T02:12:07+05:30',
      );
    });

    test('al cruzar la medianoche cambia el dia', () {
      expect(
        formatearFechaConOffset(
          DateTime.utc(2026, 10, 16, 2),
          desfase: const Duration(hours: -5),
        ),
        '2026-10-15T21:00:00-05:00',
      );
    });
  });

  group('metadatos', () {
    test('un toJson normal es valido contra el esquema', () {
      expect(validarMetadatos(_json()), isEmpty);
    });

    test('pasa por JSON de ida y vuelta sin perder validez', () {
      final String texto = jsonEncode(_muestra().toJson());

      expect(validarMetadatos(jsonDecode(texto)), isEmpty);
    });

    test('lleva exactamente las claves de la spec', () {
      final Map<String, Object?> j = _json();

      expect(j.keys.toSet(), <String>{
        'esquema',
        'seudonimo',
        'luz',
        'repeticion',
        'tarjeta_gris',
        'fecha_hora',
        'celular',
        'pantalla',
        'camara',
        'rostro',
        'perfil_color',
        'archivos',
      });
      expect((j['celular']! as Map).keys.toSet(), <String>{
        'codigo',
        'modelo',
        'sistema',
        'build_app',
      });
      expect(
        ((j['camara']! as Map)['parametros']! as Map).keys.toSet(),
        <String>{'exposicion', 'iso', 'balance_blancos'},
      );
    });

    test('los parametros de camara que no se leyeron quedan en null, no inventados', () {
      final Map<String, Object?> par =
          (_json()['camara']! as Map<String, Object?>)['parametros']!
              as Map<String, Object?>;

      expect(par['exposicion'], isNull);
      expect(par['iso'], isNull);
      expect(par['balance_blancos'], isNull);
    });

    test('los parametros que si se leyeron se guardan', () {
      final Map<String, Object?> j = _json(
        _muestra(
          parametros: const ParametrosDeCamara(
            exposicion: 0.5,
            iso: 400,
            balanceBlancos: 'auto',
          ),
        ),
      );
      final Map<String, Object?> par =
          (j['camara']! as Map<String, Object?>)['parametros']!
              as Map<String, Object?>;

      expect(par, <String, Object?>{
        'exposicion': 0.5,
        'iso': 400,
        'balance_blancos': 'auto',
      });
      expect(validarMetadatos(j), isEmpty);
    });

    test('la tarjeta gris del JSON sigue a la repeticion', () {
      expect(_json(_muestra())['tarjeta_gris'], isTrue);
      expect(
        _json(_muestra(id: idDe(repeticion: Repeticion.r2)))['tarjeta_gris'],
        isFalse,
      );
    });

    test('lente frontal y flash apagado van fijos', () {
      final Map<String, Object?> cam =
          _json()['camara']! as Map<String, Object?>;

      expect(cam['lente'], 'frontal');
      expect(cam['flash'], 'apagado');
    });

    test('camara.espejo se registra como true, false o null, sin corregir', () {
      for (final bool? valor in <bool?>[true, false, null]) {
        final Map<String, Object?> j = _json(_muestra(espejo: valor));
        final Map<String, Object?> cam = j['camara']! as Map<String, Object?>;

        expect(cam.containsKey('espejo'), isTrue);
        expect(cam['espejo'], valor);
        expect(validarMetadatos(j), isEmpty, reason: '$valor');
      }
    });
  });

  group('validacion estricta', () {
    final List<(String, void Function(Map<String, Object?>), String)> casos =
        <(String, void Function(Map<String, Object?>), String)>[
          ('falta una clave', (j) => j.remove('luz'), 'falta la clave "luz"'),
          ('clave de mas', (j) => j['extra'] = 1, 'clave no prevista "extra"'),
          ('esquema distinto', (j) => j['esquema'] = 2, 'esquema debe ser 1'),
          ('seudonimo invalido', (j) => j['seudonimo'] = 'P9', 'seudonimo'),
          ('luz invalida', (j) => j['luz'] = 'SOL', 'luz no es'),
          (
            'repeticion invalida',
            (j) => j['repeticion'] = 'R9',
            'repeticion no es',
          ),
          (
            'tarjeta no corresponde',
            (j) => j['tarjeta_gris'] = false,
            'tarjeta_gris no corresponde',
          ),
          (
            'fecha sin desfase',
            (j) => j['fecha_hora'] = '2026-10-15T15:42:07',
            'fecha_hora',
          ),
          (
            'fecha en otro formato',
            (j) => j['fecha_hora'] = '15/10/2026',
            'fecha_hora',
          ),
          (
            'celular invalido',
            (j) => (j['celular']! as Map<String, Object?>)['codigo'] = 'D9',
            'celular.codigo',
          ),
          (
            'modelo vacio',
            (j) => (j['celular']! as Map<String, Object?>)['modelo'] = '',
            'celular.modelo',
          ),
          (
            'true tone no booleano',
            (j) =>
                (j['pantalla']!
                        as Map<String, Object?>)['true_tone_o_night_shift'] =
                    'si',
            'true_tone',
          ),
          (
            'lente trasera',
            (j) => (j['camara']! as Map<String, Object?>)['lente'] = 'trasera',
            'camara.lente',
          ),
          (
            'flash encendido',
            (j) =>
                (j['camara']! as Map<String, Object?>)['flash'] = 'encendido',
            'camara.flash',
          ),
          (
            'espejo como texto',
            (j) => (j['camara']! as Map<String, Object?>)['espejo'] = 'si',
            'camara.espejo',
          ),
          (
            'espejo ausente',
            (j) => (j['camara']! as Map<String, Object?>).remove('espejo'),
            'falta la clave "espejo"',
          ),
          (
            'iso como texto',
            (j) =>
                ((j['camara']! as Map<String, Object?>)['parametros']!
                        as Map<String, Object?>)['iso'] =
                    'alto',
            'iso',
          ),
          (
            'bbox corta',
            (j) =>
                (j['rostro']! as Map<String, Object?>)['bbox'] = <num>[1, 2, 3],
            'bbox',
          ),
          (
            'bbox con texto',
            (j) => (j['rostro']! as Map<String, Object?>)['bbox'] = <Object>[
              1,
              2,
              3,
              'x',
            ],
            'bbox',
          ),
          (
            'ancho negativo',
            (j) => (j['rostro']! as Map<String, Object?>)['ancho_px'] = -1,
            'ancho_px',
          ),
          (
            'perfil de foto vacio',
            (j) => (j['perfil_color']! as Map<String, Object?>)['foto'] = '',
            'perfil_color.foto',
          ),
          (
            'foto con otro nombre',
            (j) =>
                (j['archivos']! as Map<String, Object?>)['foto'] = 'otra.jpg',
            'archivos.foto',
          ),
          (
            'recorte con otro nombre',
            (j) => (j['archivos']! as Map<String, Object?>)['recorte'] =
                'otro.png',
            'archivos.recorte',
          ),
          (
            'sha256 corto',
            (j) =>
                ((j['archivos']! as Map<String, Object?>)['sha256']!
                        as Map<String, Object?>)['foto'] =
                    'abc',
            'sha256.foto',
          ),
          (
            'sha256 en mayusculas',
            (j) =>
                ((j['archivos']! as Map<String, Object?>)['sha256']!
                        as Map<String, Object?>)['recorte'] =
                    'A' * 64,
            'sha256.recorte',
          ),
        ];

    for (final (
          String nombre,
          void Function(Map<String, Object?>) mutar,
          String esperado,
        )
        in casos) {
      test('rechaza: $nombre', () {
        final Map<String, Object?> j = _json();
        mutar(j);

        expect(validarMetadatos(j).join(' | '), contains(esperado));
      });
    }

    test('algo que no es un objeto se rechaza', () {
      expect(validarMetadatos(<Object>[1, 2]), isNotEmpty);
      expect(validarMetadatos('texto'), isNotEmpty);
      expect(validarMetadatos(null), isNotEmpty);
    });

    test('la foto es .jpg: ni .heic ni .png valen', () {
      final Map<String, Object?> j = _json();
      expect(validarMetadatos(j), isEmpty);

      for (final String ext in <String>['heic', 'png', 'jpeg']) {
        (j['archivos']! as Map<String, Object?>)['foto'] =
            'P3_LEDC_D2_R1_G_foto.$ext';
        expect(
          validarMetadatos(j).join(' | '),
          contains('archivos.foto debe llamarse P3_LEDC_D2_R1_G_foto.jpg'),
          reason: ext,
        );
      }
    });
  });
}
