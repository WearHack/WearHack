/**
 * Plataforma: lo transversal del Core.
 *
 * <p>Es un modulo compartido (ver {@code WearHackApplication}), asi que cualquier modulo
 * puede usarlo. A cambio, no puede depender de ningun modulo de negocio: un modulo
 * compartido que importa de los demas convierte las fronteras en un circulo.
 *
 * <p>Aqui viven la seguridad (validacion de los JWT de Cognito), el manejo global de
 * errores y, cuando llegue, el cliente de los servicios de IA. Nada de logica de negocio.
 *
 * <p>Lo que otros modulos pueden usar esta en este paquete raiz ({@link ErrorApi},
 * {@link ProveedorIdentidad} y las excepciones). Los subpaquetes son internos.
 */
@ApplicationModule(displayName = "Plataforma", allowedDependencies = {})
package com.wearhack.plataforma;

import org.springframework.modulith.ApplicationModule;
