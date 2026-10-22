/// Los outfits que el recomendador genero para esta semana.
///
/// Solo consulta (issue #15). Elegir el mejor de N, que es lo que alimenta las
/// preferencias, es otra pantalla (issue #16).
library;

import 'package:flutter/material.dart';
import 'package:wearhack/core/ui/estados.dart';
import 'package:wearhack/features/outfits/outfit.dart';
import 'package:wearhack/features/outfits/repositorio_outfits.dart';
import 'package:wearhack/features/outfits/ui/tarjeta_outfit.dart';

class PantallaOutfits extends StatefulWidget {
  const PantallaOutfits({super.key, required this.repositorio});

  final RepositorioOutfits repositorio;

  @override
  State<PantallaOutfits> createState() => _PantallaOutfitsState();
}

class _PantallaOutfitsState extends State<PantallaOutfits> {
  late Future<List<Outfit>> _carga = widget.repositorio.outfitsDeLaSemana();

  void _recargar() {
    setState(() {
      _carga = widget.repositorio.outfitsDeLaSemana();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Outfit>>(
      future: _carga,
      builder: (BuildContext context, AsyncSnapshot<List<Outfit>> snapshot) {
        if (snapshot.hasError) return ErrorDeCarga(onReintentar: _recargar);
        final List<Outfit>? outfits = snapshot.data;
        if (outfits == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (outfits.isEmpty) {
          return const MensajeVacio(
            icono: Icons.style_outlined,
            texto: 'Todavía no hay outfits para esta semana.',
          );
        }

        // En web la ventana puede ser muy ancha; una columna de tarjetas
        // estiradas a 1900 px no se lee.
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: outfits.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int i) => i == 0
                  ? Text(
                      'Generados a partir de tu clóset para esta semana.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : TarjetaOutfit(outfit: outfits[i - 1]),
            ),
          ),
        );
      },
    );
  }
}
