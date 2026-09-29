package com.wearhack;

import org.springframework.boot.SpringApplication;
import org.springframework.modulith.Modulith;

/**
 * El Core de WearHack: un solo deployable, modular con Spring Modulith.
 *
 * <p>Cada subpaquete directo de {@code com.wearhack} es un modulo:
 *
 * <ul>
 *   <li>{@code usuarios}: cuentas de negocio, ligadas al {@code sub} de Cognito, y el
 *       perfil de colorimetria, que es opcional.
 *   <li>{@code closet}: las prendas digitalizadas.
 *   <li>{@code outfits}: los outfits semanales y las selecciones.
 *   <li>{@code publicidad}: el catalogo de marcas aliadas y las prendas puente.
 *   <li>{@code plataforma}: lo transversal (salud, errores, seguridad, cliente de la IA).
 *       No lleva logica de negocio y no depende de ningun modulo de negocio.
 * </ul>
 *
 * <p>Las fronteras no son una convencion de nombres: cada modulo declara de quien
 * puede depender en su {@code package-info.java}, y {@code ModulithTest} lo verifica.
 * Un modulo que importe algo que no debe rompe el build.
 *
 * <p>{@code plataforma} es un modulo compartido: todos pueden usarlo sin listarlo en
 * {@code allowedDependencies}. Es lo unico que se comparte asi, a proposito.
 *
 * <p>Esqueleto. Arranca, responde /health y emite trazas. Nada mas.
 */
@Modulith(systemName = "WearHack Core", sharedModules = "plataforma")
public class WearHackApplication {

    public static void main(String[] args) {
        SpringApplication.run(WearHackApplication.class, args);
    }
}
