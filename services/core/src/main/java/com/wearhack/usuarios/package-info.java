/**
 * Usuarios: las cuentas de negocio y el perfil de colorimetria.
 *
 * <p>El Core <strong>no gestiona credenciales</strong>. Cognito emite los JWT y este
 * modulo solo vincula datos de negocio al {@code sub} del token.
 *
 * <p>El perfil de colorimetria es <strong>opcional</strong>: un usuario sin perfil es un
 * usuario valido, sin caso especial. Solo se guardan los valores de color derivados,
 * nunca el recorte facial del que salieron.
 *
 * <p>No depende de ningun otro modulo de negocio: es la base de la que dependen los demas.
 */
@ApplicationModule(displayName = "Usuarios", allowedDependencies = {})
package com.wearhack.usuarios;

import org.springframework.modulith.ApplicationModule;
