/// El texto de la autorizacion para la colorimetria.
///
/// Sale del borrador de la politica de datos (seccion 5), que es **solo un
/// punto de partida para revision legal**: falta que un abogado lo apruebe. Los
/// corchetes marcan lo que sigue sin definir.
///
/// **Si cambias algo de aqui, sube `versionTextoConsentimiento`** en
/// `consentimiento.dart`: quien autorizo el texto anterior tiene que volver a
/// verlo.
library;

import 'package:flutter/material.dart';

class SeccionConsentimiento {
  const SeccionConsentimiento(this.icono, this.titulo, this.cuerpo);

  final IconData icono;
  final String titulo;
  final String cuerpo;
}

const String introduccionConsentimiento =
    'Para calcular tu temporada de color, WearHack analiza un recorte de tu '
    'rostro. Antes de abrir la cámara necesitamos tu autorización.';

const List<SeccionConsentimiento>
seccionesConsentimiento = <SeccionConsentimiento>[
  SeccionConsentimiento(
    Icons.face_outlined,
    'Qué recolectamos',
    'Un recorte de tu rostro y, a partir de él, valores de color de tu '
        'piel, cabello y ojos. La foto completa nunca sale de tu teléfono.',
  ),
  SeccionConsentimiento(
    Icons.palette_outlined,
    'Para qué',
    'Solo para calcular tu temporada de color y personalizar tus outfits. '
        'No se usa para publicidad ni se comparte con marcas aliadas.',
  ),
  SeccionConsentimiento(
    Icons.volunteer_activism_outlined,
    'Es voluntario',
    'Son datos sensibles y entregarlos es voluntario. Puedes omitir este '
        'paso y seguir usando toda la app.',
  ),
  SeccionConsentimiento(
    Icons.schedule_outlined,
    'Qué guardamos y por cuánto tiempo',
    'El recorte de tu rostro no se guarda. Solo conservamos los valores de '
        'color y tu resultado, mientras tu cuenta esté activa o hasta que '
        'los borres.',
  ),
  SeccionConsentimiento(
    Icons.group_outlined,
    'Quién accede',
    'El equipo de WearHack y los proveedores tecnológicos que actúan por '
        'cuenta de WearHack.',
  ),
  SeccionConsentimiento(
    Icons.public,
    'Dónde',
    'El análisis se hace en servidores ubicados en Estados Unidos.',
  ),
  SeccionConsentimiento(
    Icons.gavel_outlined,
    'Tus derechos',
    'Puedes conocer, actualizar, rectificar y suprimir tus datos, y revocar '
        'esta autorización cuando quieras desde la app o escribiendo a '
        '[canal por definir].',
  ),
  SeccionConsentimiento(
    Icons.description_outlined,
    'Política de tratamiento de información',
    '[Enlace por definir]',
  ),
];

/// Todo el texto en una sola cadena, para la huella del test de version.
String textoCompletoConsentimiento() => <String>[
  introduccionConsentimiento,
  for (final SeccionConsentimiento s in seccionesConsentimiento) ...<String>[
    s.titulo,
    s.cuerpo,
  ],
].join('\n');
