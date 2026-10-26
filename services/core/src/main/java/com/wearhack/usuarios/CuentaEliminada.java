package com.wearhack.usuarios;

/**
 * Un usuario elimino su cuenta.
 *
 * <p>Usuarios borra lo suyo (perfil, perfil de colorimetria, consentimientos y
 * correcciones vinculadas) antes de publicarlo. Las prendas y los outfits son de
 * {@code closet} y {@code outfits}, que dependen de este modulo y no al reves: les toca
 * escuchar este evento y borrar lo suyo. Usuarios no puede llamarlos sin crear un ciclo.
 *
 * @param usuarioId el {@code sub} de Cognito
 */
public record CuentaEliminada(String usuarioId) {}
