/// Movimiento de la interfaz: aparecer al entrar y esperar sin spinner.
///
/// Dos reglas. El movimiento responde a algo (una pantalla que entra, datos que
/// llegan), nunca decora. Y se apaga con "reducir animaciones" del sistema:
/// `MediaQuery.disableAnimations`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Entra con un fundido y un leve ascenso, una sola vez al montarse.
///
/// En una lista, [indice] escalona la entrada: cada elemento arranca un poco
/// despues del anterior, hasta el octavo; del octavo en adelante entran juntos
/// para que una lista larga no tarde en terminar de aparecer.
///
/// [animar] en `false` lo deja ya puesto. Sirve para no repetir la entrada de
/// lo que se vuelve a construir al desplazarse por una lista.
class Aparece extends StatefulWidget {
  const Aparece({
    super.key,
    required this.child,
    this.indice = 0,
    this.animar = true,
    this.desliz = 12,
  });

  final Widget child;
  final int indice;
  final bool animar;

  /// Pixeles que sube al entrar. `0` es solo fundido.
  final double desliz;

  @override
  State<Aparece> createState() => _ApareceState();
}

class _ApareceState extends State<Aparece> with SingleTickerProviderStateMixin {
  static const int _escalonMs = 45;
  static const int _baseMs = 380;
  static const int _maxEscalones = 8;

  late final AnimationController _control;
  late final Animation<double> _t;
  bool _iniciado = false;

  @override
  void initState() {
    super.initState();
    final int retraso = math.min(widget.indice, _maxEscalones) * _escalonMs;
    final int total = _baseMs + retraso;
    _control = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    // Intervalo y no un Timer: el retraso es parte de la misma animacion y no
    // deja nada pendiente si el widget se va antes de que arranque.
    _t = CurvedAnimation(
      parent: _control,
      curve: Interval(retraso / total, 1, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    if (!widget.animar || MediaQuery.disableAnimationsOf(context)) {
      _control.value = 1;
    } else {
      _control.forward();
    }
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (BuildContext context, Widget? hijo) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * widget.desliz),
          child: hijo,
        ),
      ),
    );
  }
}

/// Pulso suave de opacidad, para los marcadores de lugar mientras carga.
class Pulso extends StatefulWidget {
  const Pulso({super.key, required this.child});

  final Widget child;

  @override
  State<Pulso> createState() => _PulsoState();
}

class _PulsoState extends State<Pulso> with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _control.value = 0.5;
    } else {
      _control.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _control, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// La cuadricula del closet o del catalogo mientras llegan los datos: cajas del
/// mismo tamano que las tarjetas, para que al llegar nada salte de sitio.
class EsqueletoCuadricula extends StatelessWidget {
  const EsqueletoCuadricula({
    super.key,
    this.anchoMaximo = 180,
    this.proporcion = 0.8,
    this.cantidad = 8,
  });

  final double anchoMaximo;
  final double proporcion;
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    return Pulso(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: anchoMaximo,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: proporcion,
        ),
        itemCount: cantidad,
        itemBuilder: (BuildContext context, int i) => DecoratedBox(
          decoration: BoxDecoration(
            color: colores.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
