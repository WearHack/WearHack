/// Metadatos de una toma, con el esquema 1 de `docs/spec-modo-captura-pruebas.md`
/// (seccion 4).
///
/// El esquema es **estricto a proposito**: [validarMetadatos] rechaza claves de
/// mas y de menos, para que un error de escritura salte aqui y no al analizar
/// 270 fotos. Un parametro de camara que el plugin no expone se guarda como
/// `null`; no se inventa.
///
/// `rostro.bbox` es `[izquierda, arriba, derecha, abajo]`, en pixeles de la
/// foto completa y ya orientada. La spec no fija el orden de los cuatro
/// numeros: este es el de `Rect` de Flutter y de ML Kit.
library;

import 'package:wearhack/features/captura_pruebas/modelos.dart';

const int versionEsquemaMetadatos = 1;

/// Lo que se sabe del celular y de la pantalla en el momento de la toma.
class DatosDelCelular {
  const DatosDelCelular({
    required this.codigo,
    required this.modelo,
    required this.sistema,
    required this.buildApp,
    required this.trueToneONightShift,
  });

  final CodigoCelular codigo;

  /// Se rellenan solos en la app (`device_info_plus`, `package_info_plus`).
  final String modelo;
  final String sistema;
  final String buildApp;

  /// iOS no permite leer True Tone ni Night Shift: lo marca el operador.
  final bool trueToneONightShift;
}

/// Parametros de camara que el plugin pudo leer. Todos pueden ser `null`.
class ParametrosDeCamara {
  const ParametrosDeCamara({this.exposicion, this.iso, this.balanceBlancos});

  final num? exposicion;
  final num? iso;
  final String? balanceBlancos;
}

class MetadatosToma {
  const MetadatosToma({
    required this.id,
    required this.fechaHora,
    required this.celular,
    required this.parametrosCamara,
    required this.espejo,
    required this.rostroBbox,
    required this.anchoRostroPx,
    required this.perfilFoto,
    required this.perfilRecorte,
    required this.archivoFoto,
    required this.archivoRecorte,
    required this.sha256Foto,
    required this.sha256Recorte,
  });

  final IdToma id;
  final DateTime fechaHora;
  final DatosDelCelular celular;
  final ParametrosDeCamara parametrosCamara;

  /// `camara.espejo`: la foto guardada esta reflejada en horizontal (`true`), no
  /// lo esta (`false`) o no se sabe (`null`). Solo se registra; no se corrige.
  final bool? espejo;

  /// `[izquierda, arriba, derecha, abajo]`.
  final List<num> rostroBbox;
  final int anchoRostroPx;
  final String perfilFoto;
  final String perfilRecorte;
  final String archivoFoto;
  final String archivoRecorte;
  final String sha256Foto;
  final String sha256Recorte;

  Map<String, Object?> toJson() => <String, Object?>{
    'esquema': versionEsquemaMetadatos,
    'seudonimo': id.seudonimo.valor,
    'luz': id.luz.codigo,
    'repeticion': id.repeticion.codigo,
    'tarjeta_gris': id.tarjetaGris,
    'fecha_hora': formatearFechaConOffset(fechaHora),
    'celular': <String, Object?>{
      'codigo': celular.codigo.codigo,
      'modelo': celular.modelo,
      'sistema': celular.sistema,
      'build_app': celular.buildApp,
    },
    'pantalla': <String, Object?>{
      'true_tone_o_night_shift': celular.trueToneONightShift,
    },
    'camara': <String, Object?>{
      'lente': 'frontal',
      'flash': 'apagado',
      'espejo': espejo,
      'parametros': <String, Object?>{
        'exposicion': parametrosCamara.exposicion,
        'iso': parametrosCamara.iso,
        'balance_blancos': parametrosCamara.balanceBlancos,
      },
    },
    'rostro': <String, Object?>{'bbox': rostroBbox, 'ancho_px': anchoRostroPx},
    'perfil_color': <String, Object?>{
      'foto': perfilFoto,
      'recorte': perfilRecorte,
    },
    'archivos': <String, Object?>{
      'foto': archivoFoto,
      'recorte': archivoRecorte,
      'sha256': <String, Object?>{'foto': sha256Foto, 'recorte': sha256Recorte},
    },
  };
}

/// ISO 8601 con el desfase respecto a UTC, por ejemplo
/// `2026-10-15T15:42:07-05:00`.
///
/// Recibe el desfase aparte para poder probarlo sin depender de la zona
/// horaria de la maquina. Por defecto usa el de [momento] en hora local.
String formatearFechaConOffset(DateTime momento, {Duration? desfase}) {
  final Duration offset = desfase ?? momento.toLocal().timeZoneOffset;
  final DateTime local = momento.toUtc().add(offset);
  String dos(int n) => n.toString().padLeft(2, '0');
  final int minutosTotales = offset.inMinutes.abs();
  final String signo = offset.isNegative ? '-' : '+';
  return '${local.year.toString().padLeft(4, '0')}-${dos(local.month)}-'
      '${dos(local.day)}T${dos(local.hour)}:${dos(local.minute)}:'
      '${dos(local.second)}$signo${dos(minutosTotales ~/ 60)}:'
      '${dos(minutosTotales % 60)}';
}

final RegExp _formatoFecha = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$',
);
final RegExp _formatoSha256 = RegExp(r'^[0-9a-f]{64}$');

/// Valida un JSON de metadatos contra el esquema 1. Devuelve una frase por
/// problema; vacio si es valido.
List<String> validarMetadatos(Object? json) {
  final List<String> p = <String>[];
  if (json is! Map<String, Object?>) return <String>['no es un objeto JSON'];

  const Set<String> clavesRaiz = <String>{
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
  };
  _claves(p, 'raiz', json, clavesRaiz);

  if (json['esquema'] != versionEsquemaMetadatos) {
    p.add('esquema debe ser $versionEsquemaMetadatos');
  }

  final Object? seudonimo = json['seudonimo'];
  final Object? luz = json['luz'];
  final Object? repeticion = json['repeticion'];
  if (seudonimo is! String || !Seudonimo.esValido(seudonimo)) {
    p.add('seudonimo debe ser P1 a P6');
  }
  if (luz is! String || Luz.desdeCodigo(luz) == null) {
    p.add('luz no es una de VEN, LEDC, LEDF, MIX, BAJ');
  }
  final Repeticion? rep = repeticion is String
      ? Repeticion.desdeCodigo(repeticion)
      : null;
  if (rep == null) p.add('repeticion no es R1, R2 o R3');
  if (json['tarjeta_gris'] is! bool) {
    p.add('tarjeta_gris debe ser booleano');
  } else if (rep != null && json['tarjeta_gris'] != rep.llevaTarjetaGris) {
    p.add(
      'tarjeta_gris no corresponde a la repeticion (solo R1 lleva tarjeta)',
    );
  }
  final Object? fecha = json['fecha_hora'];
  if (fecha is! String || !_formatoFecha.hasMatch(fecha)) {
    p.add(
      'fecha_hora debe ser ISO 8601 con desfase, p. ej. 2026-10-15T15:42:07-05:00',
    );
  }

  final Map<String, Object?>? celular = _objeto(p, 'celular', json['celular']);
  CodigoCelular? codigoCelular;
  if (celular != null) {
    _claves(p, 'celular', celular, const <String>{
      'codigo',
      'modelo',
      'sistema',
      'build_app',
    });
    final Object? c = celular['codigo'];
    codigoCelular = c is String ? CodigoCelular.desdeCodigo(c) : null;
    if (codigoCelular == null) p.add('celular.codigo no es D1, D2 o D3');
    for (final String k in <String>['modelo', 'sistema', 'build_app']) {
      if (celular[k] is! String || (celular[k] as String).isEmpty) {
        p.add('celular.$k debe ser un texto no vacio');
      }
    }
  }

  final Map<String, Object?>? pantalla = _objeto(
    p,
    'pantalla',
    json['pantalla'],
  );
  if (pantalla != null) {
    _claves(p, 'pantalla', pantalla, const <String>{'true_tone_o_night_shift'});
    if (pantalla['true_tone_o_night_shift'] is! bool) {
      p.add('pantalla.true_tone_o_night_shift debe ser booleano');
    }
  }

  final Map<String, Object?>? camara = _objeto(p, 'camara', json['camara']);
  if (camara != null) {
    _claves(p, 'camara', camara, const <String>{
      'lente',
      'flash',
      'espejo',
      'parametros',
    });
    if (camara['lente'] != 'frontal') p.add('camara.lente debe ser "frontal"');
    if (camara['flash'] != 'apagado') p.add('camara.flash debe ser "apagado"');
    if (camara['espejo'] != null && camara['espejo'] is! bool) {
      p.add('camara.espejo debe ser un booleano o null');
    }
    final Map<String, Object?>? par = _objeto(
      p,
      'camara.parametros',
      camara['parametros'],
    );
    if (par != null) {
      _claves(p, 'camara.parametros', par, const <String>{
        'exposicion',
        'iso',
        'balance_blancos',
      });
      for (final String k in <String>['exposicion', 'iso']) {
        if (par[k] != null && par[k] is! num) {
          p.add('camara.parametros.$k debe ser un numero o null');
        }
      }
      if (par['balance_blancos'] != null && par['balance_blancos'] is! String) {
        p.add('camara.parametros.balance_blancos debe ser un texto o null');
      }
    }
  }

  final Map<String, Object?>? rostro = _objeto(p, 'rostro', json['rostro']);
  if (rostro != null) {
    _claves(p, 'rostro', rostro, const <String>{'bbox', 'ancho_px'});
    final Object? bbox = rostro['bbox'];
    if (bbox is! List ||
        bbox.length != 4 ||
        bbox.any((Object? v) => v is! num)) {
      p.add('rostro.bbox debe ser una lista de 4 numeros');
    }
    if (rostro['ancho_px'] is! int || (rostro['ancho_px'] as int) < 0) {
      p.add('rostro.ancho_px debe ser un entero mayor o igual a 0');
    }
  }

  final Map<String, Object?>? perfil = _objeto(
    p,
    'perfil_color',
    json['perfil_color'],
  );
  if (perfil != null) {
    _claves(p, 'perfil_color', perfil, const <String>{'foto', 'recorte'});
    for (final String k in <String>['foto', 'recorte']) {
      if (perfil[k] is! String || (perfil[k] as String).isEmpty) {
        p.add('perfil_color.$k debe ser un texto no vacio');
      }
    }
  }

  final Map<String, Object?>? archivos = _objeto(
    p,
    'archivos',
    json['archivos'],
  );
  if (archivos != null) {
    _claves(p, 'archivos', archivos, const <String>{
      'foto',
      'recorte',
      'sha256',
    });
    final IdToma? id =
        (seudonimo is String &&
            luz is String &&
            rep != null &&
            codigoCelular != null)
        ? IdToma.desdeNombreBase(
            '${seudonimo}_${luz}_${codigoCelular.codigo}_${rep.codigo}_${rep.marcaTarjeta}',
          )
        : null;
    if (id != null) {
      final String base = id.nombreBase;
      final Object? foto = archivos['foto'];
      if (foto != '${base}_foto.jpg') {
        p.add('archivos.foto debe llamarse ${base}_foto.jpg');
      }
      if (archivos['recorte'] != '${base}_recorte.png') {
        p.add('archivos.recorte debe llamarse ${base}_recorte.png');
      }
    }
    final Map<String, Object?>? sha = _objeto(
      p,
      'archivos.sha256',
      archivos['sha256'],
    );
    if (sha != null) {
      _claves(p, 'archivos.sha256', sha, const <String>{'foto', 'recorte'});
      for (final String k in <String>['foto', 'recorte']) {
        final Object? v = sha[k];
        if (v is! String || !_formatoSha256.hasMatch(v)) {
          p.add(
            'archivos.sha256.$k debe ser un SHA-256 en hexadecimal minuscula',
          );
        }
      }
    }
  }

  return p;
}

Map<String, Object?>? _objeto(List<String> p, String nombre, Object? valor) {
  if (valor is Map<String, Object?>) return valor;
  p.add('$nombre debe ser un objeto');
  return null;
}

void _claves(
  List<String> p,
  String donde,
  Map<String, Object?> objeto,
  Set<String> esperadas,
) {
  for (final String k in esperadas) {
    if (!objeto.containsKey(k)) p.add('$donde: falta la clave "$k"');
  }
  for (final String k in objeto.keys) {
    if (!esperadas.contains(k)) p.add('$donde: clave no prevista "$k"');
  }
}
