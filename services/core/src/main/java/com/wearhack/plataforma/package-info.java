/**
 * Plataforma: lo transversal del Core.
 *
 * <p>Es un modulo compartido (ver {@code WearHackApplication}), asi que cualquier modulo
 * puede usarlo. A cambio, no puede depender de ningun modulo de negocio: un modulo
 * compartido que importa de los demas convierte las fronteras en un circulo.
 *
 * <p>Aqui iran la seguridad, el manejo global de errores y el cliente de los servicios
 * de IA. Nada de logica de negocio.
 */
@ApplicationModule(displayName = "Plataforma", allowedDependencies = {})
package com.wearhack.plataforma;

import org.springframework.modulith.ApplicationModule;
