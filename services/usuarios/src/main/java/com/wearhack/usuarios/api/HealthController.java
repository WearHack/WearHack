package com.wearhack.usuarios.api;

import java.time.Instant;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Health check de negocio, expuesto a traves del gateway.
 *
 * <p>Convive con /actuator/health a proposito y los dos tienen publicos
 * distintos. Actuator es interno: lo consulta el healthcheck de Docker y, en
 * AWS, el target group del ALB. Este otro sale al exterior por el gateway y es
 * el que se usa para comprobar la cadena completa cliente -> gateway -> servicio.
 *
 * <p>Placeholder: cuando haya logica de negocio, este controlador se queda y los
 * endpoints reales se suman al lado.
 */
@RestController
@RequestMapping("/api/v1/usuarios")
public class HealthController {

    private static final String SERVICIO = "usuarios";

    private final String version;

    public HealthController(@Value("${wearhack.version:desconocida}") String version) {
        this.version = version;
    }

    @GetMapping("/health")
    public Estado health() {
        return new Estado(SERVICIO, "UP", version, Instant.now());
    }

    /** Respuesta del health check. Igual en los cuatro servicios de negocio. */
    public record Estado(String servicio, String estado, String version, Instant momento) {}
}
