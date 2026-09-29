/**
 * Publicidad: el catalogo de marcas aliadas y las prendas puente.
 *
 * <p>Sin inventario fisico en tiempo real. Es lo que monetiza el producto.
 *
 * <p><strong>Es el primer candidato a extraerse</strong> cuando el Modulith se quede
 * corto, y por eso su frontera esta reforzada: {@code allowedDependencies} vacio
 * significa que <em>no puede depender de ningun otro modulo de negocio</em>, y
 * {@code ModulithTest} rompe el build si alguien lo intenta. El dia que haya que
 * sacarlo, es mover un paquete.
 *
 * <p>Hacia dentro, los demas modulos solo deben tocar lo que este en la raiz de este
 * paquete. Todo lo que este en un subpaquete es interno.
 */
@ApplicationModule(displayName = "Publicidad", allowedDependencies = {})
package com.wearhack.publicidad;

import org.springframework.modulith.ApplicationModule;
