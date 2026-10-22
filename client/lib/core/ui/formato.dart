/// Formatos de texto para mostrar valores.
library;

const List<String> _meses = <String>[
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Una fecha larga: `22 de octubre de 2026`.
String formatoFecha(DateTime fecha) =>
    '${fecha.day} de ${_meses[fecha.month - 1]} de ${fecha.year}';

/// Un precio en pesos colombianos: `$ 189.900`.
///
/// A mano y no con `intl`: es el unico formato que hace falta y no justifica
/// una dependencia.
String formatoPesos(int pesos) {
  final String digitos = pesos.abs().toString();
  final StringBuffer texto = StringBuffer(pesos < 0 ? '-\$ ' : '\$ ');
  for (int i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) texto.write('.');
    texto.write(digitos[i]);
  }
  return texto.toString();
}
