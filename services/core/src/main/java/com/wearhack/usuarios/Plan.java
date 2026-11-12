package com.wearhack.usuarios;

/**
 * El nivel de suscripcion de un usuario (modelo freemium B2C).
 *
 * <p>Los precios y lo que incluye cada nivel salen del modelo financiero a 36 meses del
 * equipo. Los derechos concretos de cada plan los da {@link PlanesUsuario#derechos}.
 */
public enum Plan {
    /** Sin pago. Limitado en solicitudes de IA, prendas y dress code. */
    GRATIS,
    /** COP 6.900/mes: closet ilimitado, plan semanal y dress code ilimitado. */
    ESENCIAL,
    /** COP 12.900/mes: lo de Esencial mas escaneo en tienda, analisis del closet y maleta. */
    PLUS
}
