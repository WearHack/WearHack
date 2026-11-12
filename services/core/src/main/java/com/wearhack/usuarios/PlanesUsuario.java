package com.wearhack.usuarios;

/**
 * El plan de un usuario y su cuota mensual de solicitudes de IA.
 *
 * <p>Es la puerta para los demas modulos ({@code closet}, {@code outfits}): antes de una
 * accion limitada por plan consultan {@link #derechos}, y antes de llamar a un servicio de
 * IA piden {@link #consumirSolicitudIa}.
 */
public interface PlanesUsuario {

    /** Los derechos del plan vigente. Un usuario sin perfil o sin plan guardado es {@link Plan#GRATIS}. */
    DerechosPlan derechos(String usuarioId);

    /**
     * Reserva una solicitud de IA del mes en curso. Es atomico: dos peticiones a la vez no
     * pueden pasarse del tope.
     *
     * @throws CuotaIaAgotadaException si ya se usaron todas las del mes
     */
    void consumirSolicitudIa(String usuarioId);

    /**
     * Devuelve una solicitud reservada que no llego a servirse (la IA fallo o el recorte no
     * servia). No baja de cero.
     */
    void devolverSolicitudIa(String usuarioId);

    /** Solicitudes de IA usadas en el mes en curso. */
    int solicitudesIaUsadas(String usuarioId);
}
