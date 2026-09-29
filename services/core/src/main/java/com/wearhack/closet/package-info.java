/**
 * Closet: las prendas digitalizadas de cada usuario.
 *
 * <p>La clasificacion (quitar el fondo, color base, tipo, textura y patron) corre en el
 * dispositivo. Este modulo recibe la prenda ya procesada y sus atributos; nunca la foto
 * original ni un servicio que clasifique.
 *
 * <p>Depende solo de {@code usuarios}, para saber de quien es cada prenda.
 */
@ApplicationModule(displayName = "Closet", allowedDependencies = {"usuarios"})
package com.wearhack.closet;

import org.springframework.modulith.ApplicationModule;
