/**
 * Outfits: los outfits semanales y las selecciones del usuario.
 *
 * <p>Genera los outfits llamando de forma sincrona al servicio {@code recomendacion}, y
 * <strong>le manda las prendas candidatas en el propio request</strong>: la IA no consulta
 * la base de datos. Si la IA no responde a tiempo, el modulo degrada con un mensaje
 * controlado y sin perder datos.
 *
 * <p>Depende de {@code usuarios}, de {@code closet} (las prendas) y de {@code publicidad}
 * (las prendas puente). Es el modulo con mas dependencias, y las tres estan declaradas.
 */
@ApplicationModule(
        displayName = "Outfits",
        allowedDependencies = {"usuarios", "closet", "publicidad"})
package com.wearhack.outfits;

import org.springframework.modulith.ApplicationModule;
