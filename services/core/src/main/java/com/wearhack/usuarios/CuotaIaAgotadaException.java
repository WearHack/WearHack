package com.wearhack.usuarios;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/**
 * El usuario ya uso todas las solicitudes de IA de su plan este mes. Se responde con 429:
 * en el B2C no hay cobro por solicitud extra, el consumo se controla con el tope.
 */
public class CuotaIaAgotadaException extends ResponseStatusException {

    public CuotaIaAgotadaException(Plan plan, int limite) {
        super(HttpStatus.TOO_MANY_REQUESTS, "Ya usaste las " + limite + " solicitudes de IA del plan "
                + plan + " este mes. Se renuevan el primer dia del mes siguiente");
    }
}
