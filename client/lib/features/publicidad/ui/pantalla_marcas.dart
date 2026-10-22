/// Marcas aliadas: el ranking de prendas puente del usuario y el catalogo de
/// cada marca (issue #18).
///
/// Es la pantalla que monetiza el producto, y por eso la mas delicada: todo lo
/// que se muestra se presenta como contenido de marcas aliadas, y nada se apoya
/// en el perfil de colorimetria, que la politica de datos excluye de la
/// publicidad.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/outfits/contexto.dart';
import 'package:wearhack/features/publicidad/catalogo.dart';
import 'package:wearhack/features/publicidad/repositorio_publicidad.dart';
import 'package:wearhack/features/publicidad/ui/pantalla_catalogo.dart';
import 'package:wearhack/features/publicidad/ui/pantalla_prenda_puente.dart';

class PantallaMarcas extends StatefulWidget {
  const PantallaMarcas({super.key, required this.repositorio});

  final RepositorioPublicidad repositorio;

  @override
  State<PantallaMarcas> createState() => _PantallaMarcasState();
}

class _PantallaMarcasState extends State<PantallaMarcas> {
  late Future<(List<PrendaPuente>, List<MarcaAliada>)> _carga = _cargar();

  Future<(List<PrendaPuente>, List<MarcaAliada>)> _cargar() async => (
    await widget.repositorio.prendasPuente(),
    await widget.repositorio.marcas(),
  );

  void _recargar() {
    setState(() {
      _carga = _cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<PrendaPuente>, List<MarcaAliada>)>(
      future: _carga,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<(List<PrendaPuente>, List<MarcaAliada>)> snapshot,
          ) {
            if (snapshot.hasError) return ErrorDeCarga(onReintentar: _recargar);
            final (List<PrendaPuente>, List<MarcaAliada>)? datos =
                snapshot.data;
            if (datos == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final (List<PrendaPuente> puentes, List<MarcaAliada> marcas) =
                datos;
            final Map<String, PrendaPuente> porProducto =
                <String, PrendaPuente>{
                  for (final PrendaPuente p in puentes) p.producto.id: p,
                };
            final TextTheme texto = Theme.of(context).textTheme;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    Text('Prendas puente para ti', style: texto.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Piezas de marcas aliadas que, con lo que ya tienes, '
                      'abren combinaciones nuevas.',
                      style: texto.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    if (puentes.isEmpty)
                      const MensajeVacio(
                        icono: Icons.auto_awesome_outlined,
                        texto:
                            'Todavía no hay prendas puente para tu clóset. '
                            'Agrega más prendas y vuelve a mirar.',
                      )
                    else
                      for (int i = 0; i < puentes.length; i++)
                        _TarjetaPuente(
                          posicion: i + 1,
                          puente: puentes[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PantallaPrendaPuente(puente: puentes[i]),
                            ),
                          ),
                        ),
                    const SizedBox(height: 24),
                    Text('Marcas aliadas', style: texto.titleMedium),
                    const SizedBox(height: 4),
                    for (final MarcaAliada m in marcas)
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text(m.nombre[0])),
                          title: Text(m.nombre),
                          subtitle: Text(m.descripcion),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PantallaCatalogo(
                                repositorio: widget.repositorio,
                                marca: m,
                                puentes: porProducto,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
    );
  }
}

class _TarjetaPuente extends StatelessWidget {
  const _TarjetaPuente({
    required this.posicion,
    required this.puente,
    required this.onTap,
  });

  final int posicion;
  final PrendaPuente puente;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final ColorScheme colores = Theme.of(context).colorScheme;
    final ProductoCatalogo producto = puente.producto;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 32,
                child: Text('#$posicion', style: texto.titleMedium),
              ),
              MuestraPrenda(prenda: producto.prenda, tamano: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(producto.nombre, style: texto.titleSmall),
                    Text(
                      '${producto.marca.nombre} · '
                      '${formatoPesos(producto.precioPesos)}',
                      style: texto.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Abre ${puente.combinacionesBuenas} combinaciones',
                      style: texto.labelLarge?.copyWith(color: colores.primary),
                    ),
                    if (puente.ocasionesNuevas.isNotEmpty)
                      Text(
                        'Nuevo para ti: '
                        '${puente.ocasionesNuevas.map((Ocasion o) => o.etiqueta).join(', ')}',
                        style: texto.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
