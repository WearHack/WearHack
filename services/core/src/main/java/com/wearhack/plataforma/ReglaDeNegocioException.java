package com.wearhack.plataforma;

/**
 * La peticion esta bien formada pero el dominio no la acepta, como registrarse sin
 * declarar la mayoria de edad. Se responde con 422.
 */
public class ReglaDeNegocioException extends RuntimeException {

    public ReglaDeNegocioException(String mensaje) {
        super(mensaje);
    }
}
