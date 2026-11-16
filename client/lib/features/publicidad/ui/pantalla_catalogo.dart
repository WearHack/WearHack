/// El catalogo de una marca aliada. Las prendas que son puente para el usuario
/// van marcadas y llevan a su detalle.
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/core/ui/formato.dart';
import 'package:wearhack/core/ui/movimiento.dart';
import 'package:wearhack/features/closet/ui/muestra_prenda.dart';
import 'package:wearhack/features/publicidad/catalogo.dart';
import 'package:wearhack/features/publicidad/repositorio_publicidad.dart';
import 'package:wearhack/features/publicidad/ui/pantalla_prenda_puente.dart';

class PantallaCatalogo extends StatefulWidget {
  const PantallaCatalogo({
    super.key,
    required this.repositorio,
    required this.marca,
    required this.puentes,
  });

  final RepositorioPublicidad repositorio;
  final MarcaAliada marca;

  /// Las prendas puente del usuario, por id de producto.
  final Map<String, PrendaPuente> puentes;

  @override
  State<PantallaCatalogo> createState() => _PantallaCatalogoState();
}

class _PantallaCatalogoState extends State<PantallaCatalogo> {
  late Future<List<ProductoCatalogo>> _carga = widget.repositorio.catalogo(
    widget.marca.id,
  );

  void _recargar() {
    setState(() {
      _carga = widget.repositorio.catalogo(widget.marca.id);
    });
  }

  void _abrir(PrendaPuente puente) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaPrendaPuente(puente: puente),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.marca.nombre)),
      body: FutureBuilder<List<ProductoCatalogo>>(
        future: _carga,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<ProductoCatalogo>> snapshot,
            ) {
              if (snapshot.hasError) {
                return ErrorDeCarga(onReintentar: _recargar);
              }
              final List<ProductoCatalogo>? productos = snapshot.data;
              if (productos == null) {
                return const EsqueletoCuadricula(
                  anchoMaximo: 200,
                  proporcion: 0.7,
                  cantidad: 6,
                );
              }
              if (productos.isEmpty) {
                return const MensajeVacio(
                  icono: Icons.storefront_outlined,
                  texto: 'Esta marca todavía no tiene productos.',
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.7,
                ),
                itemCount: productos.length,
                itemBuilder: (BuildContext context, int i) {
                  final PrendaPuente? puente = widget.puentes[productos[i].id];
                  return Aparece(
                    key: ValueKey<String>(productos[i].id),
                    indice: i,
                    child: _TarjetaProducto(
                      producto: productos[i],
                      esPuente: puente != null,
                      onTap: puente == null ? null : () => _abrir(puente),
                    ),
                  );
                },
              );
            },
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({
    required this.producto,
    required this.esPuente,
    required this.onTap,
  });

  final ProductoCatalogo producto;
  final bool esPuente;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme texto = Theme.of(context).textTheme;
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: esPuente
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colores.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: MuestraPrenda(prenda: producto.prenda)),
              const SizedBox(height: 8),
              Text(
                producto.nombre,
                style: texto.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(formatoPesos(producto.precioPesos), style: texto.bodySmall),
              if (esPuente) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  'Prenda puente',
                  style: texto.labelSmall?.copyWith(color: colores.primary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
