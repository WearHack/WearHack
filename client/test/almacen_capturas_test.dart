/// El almacen privado y el servicio que registra las tomas.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:wearhack/core/color/jpeg_icc.dart';
import 'package:wearhack/core/recorte/recortador_facial.dart';
import 'package:wearhack/features/captura_pruebas/almacen_capturas.dart';
import 'package:wearhack/features/captura_pruebas/metadatos.dart';
import 'package:wearhack/features/captura_pruebas/modelos.dart';
import 'package:wearhack/features/captura_pruebas/servicio_captura.dart';

import 'helpers/captura_helpers.dart';
import 'helpers/icc_sintetico.dart';

void main() {
  late Directory raiz;

  setUp(() async => raiz = await carpetaTemporal());
  tearDown(() async {
    if (await raiz.exists()) await raiz.delete(recursive: true);
  });

  group('donde se guarda', () {
    test('se niega a trabajar dentro del repositorio', () {
      // `flutter test` corre dentro de client/, que esta dentro del repositorio.
      final Directory dentro = Directory(
        p.join(Directory.current.path, 'captura_que_no_debe_existir'),
      );

      expect(
        () => AlmacenCapturas(dentro),
        throwsA(isA<AlmacenDentroDelRepositorio>()),
      );
      expect(
        dentro.existsSync(),
        isFalse,
        reason: 'ni siquiera crea la carpeta',
      );
    });

    test('tampoco acepta una carpeta nueva bajo el repositorio, por profunda que sea', () {
      expect(
        () => AlmacenCapturas(
          Directory(p.join(Directory.current.path, 'a', 'b', 'c')),
        ),
        throwsA(isA<AlmacenDentroDelRepositorio>()),
      );
    });

    test('acepta el directorio temporal del sistema', () {
      expect(() => AlmacenCapturas(raiz), returnsNormally);
    });

    test('se niega aunque la ruta sea relativa', () {
      expect(
        () => AlmacenCapturas(Directory('captura_relativa')),
        throwsA(isA<AlmacenDentroDelRepositorio>()),
      );
    });
  });

  group('guardar una toma', () {
    late AlmacenCapturas almacen;
    late Uint8List foto;
    late RecorteFacial recorte;

    setUp(() async {
      almacen = AlmacenCapturas(raiz);
      foto = fotoDePrueba();
      recorte = (await recortadorReal().recortar(foto))!;
    });

    Future<MetadatosToma> guardar({
      IdToma? id,
      String ext = 'jpg',
      bool reemplazar = false,
      Uint8List? fotoBytes,
    }) => almacen.guardarToma(
      id: id ?? idDe(),
      foto: fotoBytes ?? foto,
      extensionFoto: ext,
      recorte: recorte,
      celular: datosDelCelular(),
      parametrosCamara: const ParametrosDeCamara(),
      momento: DateTime.utc(2026, 10, 15, 20, 42, 7),
      reemplazar: reemplazar,
    );

    test(
      'escribe foto, recorte y json con los nombres de la convencion',
      () async {
        await guardar();

        expect(await archivosBajo(almacen.dirTomas), <String>[
          'P3_LEDC_D2_R1_G.json',
          'P3_LEDC_D2_R1_G_foto.jpg',
          'P3_LEDC_D2_R1_G_recorte.png',
        ]);
      },
    );

    test(
      'la foto se guarda byte a byte y conserva su perfil de color',
      () async {
        await guardar();

        final Uint8List guardada = File(
          p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_foto.jpg'),
        ).readAsBytesSync();
        expect(guardada, foto);
        expect(
          extraerIccDeJpeg(guardada),
          perfilDisplayP3(descripcion: tagDescV2('Display P3')),
        );
      },
    );

    test('el recorte guardado es el PNG del recortador, sin tocar', () async {
      await guardar();

      expect(
        File(p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_recorte.png'))
            .readAsBytesSync(),
        recorte.png,
      );
    });

    test('el json es valido y sus hashes son los de los archivos', () async {
      await guardar();

      final Map<String, Object?> json = await almacen.leerMetadatos(idDe());
      expect(validarMetadatos(json), isEmpty);
      final Map<String, Object?> sha =
          (json['archivos']! as Map<String, Object?>)['sha256']!
              as Map<String, Object?>;
      expect(sha['foto'], sha256.convert(foto).toString());
      expect(sha['recorte'], sha256.convert(recorte.png).toString());
    });

    test('anota el rostro, el perfil y la tarjeta', () async {
      await guardar();

      final Map<String, Object?> json = await almacen.leerMetadatos(idDe());
      expect(json['tarjeta_gris'], isTrue);
      final Map<String, Object?> rostro =
          json['rostro']! as Map<String, Object?>;
      expect(rostro['bbox'], <num>[100, 100, 250, 270]);
      expect(rostro['ancho_px'], 150);
      final Map<String, Object?> perfil =
          json['perfil_color']! as Map<String, Object?>;
      expect(perfil['foto'], 'Display P3');
      expect(perfil['recorte'], perfilDelRecorte);
    });

    test('no deja archivos temporales', () async {
      await guardar();

      expect(
        (await archivosBajo(almacen.dirTomas))
            .where((String r) => r.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('una toma repetida se rechaza sin tocar la anterior', () async {
      await guardar();
      final Uint8List antes = File(
        p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_foto.jpg'),
      ).readAsBytesSync();

      await expectLater(
        guardar(fotoBytes: fotoDePrueba(semilla: 5)),
        throwsA(isA<TomaYaExiste>()),
      );

      expect(
        File(p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_foto.jpg'))
            .readAsBytesSync(),
        antes,
      );
    });

    test('reemplazar deja una sola toma con el contenido nuevo', () async {
      await guardar();
      final Uint8List nueva = fotoDePrueba(semilla: 5);

      await guardar(reemplazar: true, fotoBytes: nueva);

      expect(await almacen.listarTomas(), hasLength(1));
      expect(
        File(p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_foto.jpg'))
            .readAsBytesSync(),
        nueva,
      );
      expect(await archivosBajo(almacen.dirTomas), hasLength(3));
    });

    test('reemplazar una toma no toca las demas', () async {
      await guardar();
      await guardar(id: idDe(luz: Luz.ven));

      await guardar(reemplazar: true);

      expect(await almacen.listarTomas(), hasLength(2));
      expect(await archivosBajo(almacen.dirTomas), hasLength(6));
    });

    test('una extension que no es jpg (heic incluida) se rechaza y no escribe nada', () async {
      for (final String ext in <String>['png', 'heic', 'heif']) {
        await expectLater(guardar(ext: ext), throwsArgumentError);
      }

      expect(await archivosBajo(raiz), isEmpty);
    });

    test('la extension acepta mayusculas y punto', () async {
      await guardar(ext: '.JPG');

      expect(
        await archivosBajo(almacen.dirTomas),
        contains('P3_LEDC_D2_R1_G_foto.jpg'),
      );
    });

    test(
      'un celular que no es el de la toma se rechaza y no escribe nada',
      () async {
        await expectLater(
          almacen.guardarToma(
            id: idDe(celular: CodigoCelular.d1),
            foto: foto,
            extensionFoto: 'jpg',
            recorte: recorte,
            celular: datosDelCelular(codigo: CodigoCelular.d2),
            parametrosCamara: const ParametrosDeCamara(),
            momento: DateTime.utc(2026),
          ),
          throwsArgumentError,
        );

        expect(await archivosBajo(raiz), isEmpty);
      },
    );

    test('listarTomas devuelve las tomas ordenadas por nombre', () async {
      await guardar(id: idDe(luz: Luz.ven));
      await guardar(id: idDe(seudonimo: 'P1'));
      await guardar(id: idDe(repeticion: Repeticion.r2));

      expect(
        (await almacen.listarTomas()).map((IdToma t) => t.nombreBase),
        <String>['P1_LEDC_D2_R1_G', 'P3_LEDC_D2_R2_N', 'P3_VEN_D2_R1_G'],
      );
    });
  });

  group('integridad', () {
    late AlmacenCapturas almacen;

    setUp(() async => almacen = await almacenConTomas(raiz, 3));

    test('un lote sano no tiene problemas', () async {
      expect(await almacen.verificarIntegridad(), isEmpty);
    });

    test('un byte cambiado en la foto se detecta', () async {
      final File f = (await almacen.archivosDelLote()).firstWhere(
        (File x) => x.path.endsWith('_foto.jpg'),
      );
      final Uint8List bytes = f.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0xFF;
      f.writeAsBytesSync(bytes);

      final List<String> problemas = await almacen.verificarIntegridad();

      expect(problemas.join(' | '), contains('SHA-256'));
    });

    test('un archivo que falta se detecta', () async {
      final File f = (await almacen.archivosDelLote()).firstWhere(
        (File x) => x.path.endsWith('_recorte.png'),
      );
      f.deleteSync();

      expect(
        (await almacen.verificarIntegridad()).join(' | '),
        contains('falta'),
      );
    });

    test(
      'un archivo de mas (por ejemplo un temporal huerfano) se detecta',
      () async {
        File(p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_foto.jpg.tmp'))
            .writeAsBytesSync(<int>[1]);

        expect(
          (await almacen.verificarIntegridad()).join(' | '),
          contains('sobra'),
        );
      },
    );

    test('un json mal formado se detecta', () async {
      final File json = (await almacen.archivosDelLote()).firstWhere(
        (File x) => x.path.endsWith('.json'),
      );
      json.writeAsStringSync('{ esto no es json');

      expect(
        (await almacen.verificarIntegridad()).join(' | '),
        contains('no es un JSON valido'),
      );
    });

    test('un json que no cumple el esquema se detecta', () async {
      final File json = (await almacen.archivosDelLote()).firstWhere(
        (File x) => x.path.endsWith('.json'),
      );
      final Map<String, Object?> contenido =
          jsonDecode(json.readAsStringSync()) as Map<String, Object?>;
      contenido['luz'] = 'SOL';
      json.writeAsStringSync(jsonEncode(contenido));

      expect(
        (await almacen.verificarIntegridad()).join(' | '),
        contains('luz'),
      );
    });
  });

  group('registrar una toma con el recorte real', () {
    late AlmacenCapturas almacen;
    late CropperDePrueba cropper;
    late ServicioCapturaPruebas servicio;

    setUp(() {
      almacen = AlmacenCapturas(raiz);
      cropper = CropperDePrueba();
      servicio = ServicioCapturaPruebas(almacen: almacen, cropper: cropper);
    });

    Future<ResultadoRegistro> registrar({
      bool autorizacion = true,
      IdToma? id,
      Uint8List? foto,
      bool reemplazar = false,
    }) => servicio.registrarToma(
      id: id ?? idDe(),
      autorizacionFirmada: autorizacion,
      foto: foto ?? fotoDePrueba(),
      celular: datosDelCelular(),
      // Sin parametrosCamara: es lo que hace la app, y asi el servicio los lee
      // del EXIF de la foto.
      momento: DateTime.utc(2026, 10, 15, 20, 42, 7),
      reemplazar: reemplazar,
    );

    test('llama una vez al recorte, con la foto original', () async {
      final Uint8List foto = fotoDePrueba();

      await registrar(foto: foto);

      expect(cropper.llamadas, 1);
      expect(cropper.ultimaEntrada, foto);
    });

    test('el recorte guardado es identico al que produce la funcion real con la misma entrada', () async {
      final Uint8List foto = fotoDePrueba();

      await registrar(foto: foto);

      final RecorteFacial? independiente = await recortadorReal().recortar(
        foto,
      );
      final Uint8List guardado = File(
        p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_recorte.png'),
      ).readAsBytesSync();
      expect(guardado, independiente!.png);
      expect(sha256.convert(guardado), sha256.convert(independiente.png));
    });

    test(
      'sin la autorizacion firmada no toca ni el recorte ni el disco',
      () async {
        await expectLater(
          registrar(autorizacion: false),
          throwsA(isA<AutorizacionNoConfirmada>()),
        );

        expect(cropper.llamadas, 0);
        expect(await archivosBajo(raiz), isEmpty);
      },
    );

    test('sin rostro no guarda nada y lo dice', () async {
      final ServicioCapturaPruebas sinRostro = ServicioCapturaPruebas(
        almacen: almacen,
        cropper: CropperDePrueba(cajas: <CajaRostro>[]),
      );

      await expectLater(
        sinRostro.registrarToma(
          id: idDe(),
          autorizacionFirmada: true,
          foto: fotoDePrueba(),
          celular: datosDelCelular(),
          parametrosCamara: const ParametrosDeCamara(),
          momento: DateTime.utc(2026),
        ),
        throwsA(isA<SinRostro>()),
      );

      expect(await archivosBajo(raiz), isEmpty);
    });

    test('un perfil que no se sabe leer falla y no guarda nada', () async {
      final Uint8List lut = construirPerfil(
        rojo: const (0.4, 0.2, 0.0),
        verde: const (0.4, 0.7, 0.1),
        azul: const (0.1, 0.1, 0.7),
        curva: curvaSrgbParametrica(),
        incluirMatriz: false,
      );
      final Uint8List foto = jpegConIcc(jpegSintetico(400, 400), lut);

      await expectLater(registrar(foto: foto), throwsA(anything));

      expect(await archivosBajo(raiz), isEmpty);
    });

    test('R1 queda con tarjeta y R2 sin ella en el json', () async {
      await registrar();
      await registrar(id: idDe(repeticion: Repeticion.r2));

      expect((await almacen.leerMetadatos(idDe()))['tarjeta_gris'], isTrue);
      expect(
        (await almacen.leerMetadatos(
          idDe(repeticion: Repeticion.r2),
        ))['tarjeta_gris'],
        isFalse,
      );
    });

    Uint8List fotoConIso(int iso) {
      final img.Image im = img.Image(width: 400, height: 400);
      for (final img.Pixel p in im) {
        p
          ..r = 150
          ..g = 120
          ..b = 100;
      }
      im.exif.exifIfd[0x8827] = img.IfdValueLong(iso); // ISOSpeed
      im.exif.exifIfd[0x829a] = img.IfdValueRational(1, 100); // ExposureTime
      im.exif.exifIfd[0xa403] = img.IfdValueShort(0); // WhiteBalance auto
      return img.encodeJpg(im, quality: 95);
    }

    Map<String, Object?> parametrosGuardados(Map<String, Object?> json) =>
        (json['camara']! as Map<String, Object?>)['parametros']!
            as Map<String, Object?>;

    test('sin parametros explicitos los lee del EXIF de la foto', () async {
      await registrar(foto: fotoConIso(400));

      final Map<String, Object?> par = parametrosGuardados(
        await almacen.leerMetadatos(idDe()),
      );
      expect(par['iso'], 400);
      expect(par['exposicion'], closeTo(0.01, 1e-6));
      expect(par['balance_blancos'], 'auto');
    });

    test(
      'una foto sin EXIF deja los parametros en null, no inventados',
      () async {
        await registrar();

        final Map<String, Object?> par = parametrosGuardados(
          await almacen.leerMetadatos(idDe()),
        );
        expect(par['iso'], isNull);
        expect(par['exposicion'], isNull);
        expect(par['balance_blancos'], isNull);
      },
    );

    test('unos parametros explicitos mandan sobre el EXIF', () async {
      await servicio.registrarToma(
        id: idDe(),
        autorizacionFirmada: true,
        foto: fotoConIso(400),
        celular: datosDelCelular(),
        parametrosCamara: const ParametrosDeCamara(iso: 800),
        momento: DateTime.utc(2026, 10, 15, 20, 42, 7),
      );

      final Map<String, Object?> par = parametrosGuardados(
        await almacen.leerMetadatos(idDe()),
      );
      expect(par['iso'], 800);
      expect(
        par['exposicion'],
        isNull,
        reason: 'lo explicito no se mezcla con el EXIF',
      );
    });

    test('repetir una toma exige reemplazar', () async {
      await registrar();

      await expectLater(registrar(), throwsA(isA<TomaYaExiste>()));
      await registrar(reemplazar: true);

      expect(await almacen.listarTomas(), hasLength(1));
    });
  });

  group('el espejo de la camara frontal', () {
    Future<Map<String, Object?>> guardarConEspejo(bool? espejo) async {
      final AlmacenCapturas almacen = AlmacenCapturas(raiz);
      await ServicioCapturaPruebas(
        almacen: almacen,
        cropper: CropperDePrueba(),
      ).registrarToma(
        id: idDe(),
        autorizacionFirmada: true,
        foto: fotoDePrueba(),
        celular: datosDelCelular(),
        parametrosCamara: const ParametrosDeCamara(),
        momento: DateTime.utc(2026, 10, 15, 20, 42, 7),
        espejo: espejo,
      );
      return (await almacen.leerMetadatos(idDe()))['camara']!
          as Map<String, Object?>;
    }

    test('se registra tal cual lo informa la camara', () async {
      expect((await guardarConEspejo(true))['espejo'], isTrue);
    });

    test('si la camara no lo sabe queda en null, no en false', () async {
      final Map<String, Object?> cam = await guardarConEspejo(null);

      expect(cam.containsKey('espejo'), isTrue);
      expect(cam['espejo'], isNull);
    });

    test('la foto guardada no se toca: el espejo no se corrige', () async {
      final Uint8List foto = fotoDePrueba();
      final AlmacenCapturas almacen = AlmacenCapturas(raiz);
      await ServicioCapturaPruebas(
        almacen: almacen,
        cropper: CropperDePrueba(),
      ).registrarToma(
        id: idDe(),
        autorizacionFirmada: true,
        foto: foto,
        celular: datosDelCelular(),
        parametrosCamara: const ParametrosDeCamara(),
        momento: DateTime.utc(2026),
        espejo: true,
      );

      expect(
        File(p.join(almacen.dirTomas.path, 'P3_LEDC_D2_R1_G_foto.jpg'))
            .readAsBytesSync(),
        foto,
      );
    });
  });

  group('tomas incompletas', () {
    late AlmacenCapturas almacen;

    setUp(() async => almacen = await almacenConTomas(raiz, 2));

    File suelto(String nombre, [List<int> bytes = const <int>[1, 2, 3]]) =>
        File(p.join(almacen.dirTomas.path, nombre))..writeAsBytesSync(bytes);

    test('un lote sano no tiene ninguna', () async {
      expect(await almacen.archivosIncompletos(), isEmpty);
    });

    test('sin carpeta de tomas tampoco', () async {
      expect(
        await AlmacenCapturas(await carpetaTemporal()).archivosIncompletos(),
        isEmpty,
      );
    });

    test('la foto o el recorte sin su json son incompletos', () async {
      suelto('P3_LEDF_D2_R1_G_foto.jpg');
      suelto('P3_MIX_D2_R2_N_recorte.png');

      expect(
        (await almacen.archivosIncompletos())
            .map((File f) => p.basename(f.path))
            .toList(),
        <String>['P3_LEDF_D2_R1_G_foto.jpg', 'P3_MIX_D2_R2_N_recorte.png'],
      );
    });

    test(
      'un .tmp a medio escribir es incompleto, aunque su toma exista',
      () async {
        suelto('P3_VEN_D2_R1_G_foto.jpg.tmp');
        suelto('P3_LEDC_D2_R1_G.json.tmp');

        expect(
          (await almacen.archivosIncompletos())
              .map((File f) => p.basename(f.path))
              .toList(),
          <String>['P3_LEDC_D2_R1_G.json.tmp', 'P3_VEN_D2_R1_G_foto.jpg.tmp'],
        );
      },
    );

    test('un archivo que no es de ninguna toma tambien cuenta', () async {
      suelto('notas.txt');

      expect(await almacen.archivosIncompletos(), hasLength(1));
    });

    test(
      'una toma completa nunca aparece, sea de la persona que sea',
      () async {
        await agregarTomas(almacen, 3, seudonimo: 'P6');
        suelto('P6_BAJ_D2_R1_G_foto.jpg');

        expect(
          (await almacen.archivosIncompletos())
              .map((File f) => p.basename(f.path))
              .toList(),
          <String>['P6_BAJ_D2_R1_G_foto.jpg'],
        );
      },
    );

    test('borrar los incompletos deja las tomas completas intactas', () async {
      final List<String> antes = await archivosBajo(almacen.dirTomas);
      suelto('P3_LEDF_D2_R1_G_foto.jpg');
      suelto('P3_VEN_D2_R1_G_foto.jpg.tmp');
      suelto('P3_BAJ_D2_R3_N_recorte.png');

      final int n = await almacen.borrarIncompletos();

      expect(n, 3);
      expect(await archivosBajo(almacen.dirTomas), antes);
      expect(await almacen.verificarIntegridad(), isEmpty);
      expect(await almacen.borrarIncompletos(), 0);
    });

    test('despues de borrarlos el lote se puede exportar otra vez', () async {
      suelto('P3_LEDF_D2_R1_G_foto.jpg');
      expect(await almacen.verificarIntegridad(), isNotEmpty);

      await almacen.borrarIncompletos();

      expect(await almacen.verificarIntegridad(), isEmpty);
    });

    test('una toma a medio reemplazar deja huerfanos, y se limpian', () async {
      // Reemplazar borra el json primero: si se corta ahi, quedan la foto y el
      // recorte viejos sin json.
      File(p.join(almacen.dirTomas.path, 'P3_VEN_D2_R1_G.json')).deleteSync();

      expect(await almacen.listarTomas(), hasLength(1));
      expect(await almacen.archivosIncompletos(), hasLength(2));
      expect(await almacen.borrarIncompletos(), 2);
    });
  });

  group('por persona', () {
    test('listar, archivos e integridad se acotan a la persona', () async {
      final AlmacenCapturas almacen = await almacenConTomas(raiz, 2);
      await agregarTomas(almacen, 3, seudonimo: 'P4');
      final Seudonimo p3 = Seudonimo('P3');
      final Seudonimo p4 = Seudonimo('P4');

      expect(await almacen.listarTomas(), hasLength(5));
      expect(await almacen.listarTomas(persona: p3), hasLength(2));
      expect(await almacen.listarTomas(persona: p4), hasLength(3));
      expect(await almacen.archivosDelLote(persona: p3), hasLength(6));
      expect(await almacen.archivosDelLote(persona: p4), hasLength(9));
      expect(await almacen.archivosDelLote(persona: Seudonimo('P5')), isEmpty);

      File(p.join(almacen.dirTomas.path, 'P4_BAJ_D2_R3_N_foto.jpg'))
          .writeAsBytesSync(<int>[9]);
      expect(await almacen.verificarIntegridad(persona: p3), isEmpty);
      expect(await almacen.verificarIntegridad(persona: p4), isNotEmpty);
      expect(await almacen.verificarIntegridad(), isNotEmpty);
    });
  });
}
