package com.wearhack.closet.prendas;

import com.wearhack.usuarios.CuentaEliminada;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Borra las prendas del usuario cuando elimina su cuenta.
 *
 * <p>Sincrono a proposito: corre dentro de la peticion de borrado, antes de que Usuarios borre
 * la cuenta de Cognito. Si falla, el borrado entero falla y el usuario puede reintentar con su
 * cuenta intacta, en vez de quedar prendas huerfanas que ya nadie puede pedir que se borren.
 */
@Component
class BorradoAlEliminarCuenta {

    private final PrendasService prendas;

    BorradoAlEliminarCuenta(PrendasService prendas) {
        this.prendas = prendas;
    }

    @EventListener
    void alEliminarCuenta(CuentaEliminada evento) {
        prendas.borrarTodoDe(evento.usuarioId());
    }
}
