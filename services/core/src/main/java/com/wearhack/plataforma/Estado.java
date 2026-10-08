package com.wearhack.plataforma;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;

/**
 * Respuesta de los health checks de negocio.
 *
 * <p>Vive en {@code plataforma}, que es un modulo compartido, para que cada modulo
 * responda con la misma forma sin depender de otro modulo de negocio. Los health
 * checks de negocio conviven con {@code /actuator/health}, que es el interno: aquel
 * lo consulta el healthcheck de Docker, y estos comprueban que el modulo esta
 * cableado y responde por HTTP.
 *
 * @param servicio siempre {@code core}: es un solo deployable
 * @param modulo el modulo que responde, o {@code null} si responde el Core entero
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record Estado(
        String servicio, String modulo, String estado, String version, Instant momento) {

    /** El nombre del deployable. Antes cada modulo era un servicio con su nombre. */
    public static final String SERVICIO = "core";

    /** El Core entero, sin nombrar un modulo. */
    public static Estado arriba(String version) {
        return new Estado(SERVICIO, null, "UP", version, Instant.now());
    }

    /** Un modulo concreto del Core. */
    public static Estado arriba(String modulo, String version) {
        return new Estado(SERVICIO, modulo, "UP", version, Instant.now());
    }
}
