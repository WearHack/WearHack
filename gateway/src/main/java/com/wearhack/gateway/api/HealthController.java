package com.wearhack.gateway.api;

import java.time.Instant;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;

/**
 * Health del propio gateway.
 *
 * <p>Responde si el gateway esta en pie, sin mirar a los servicios de abajo.
 * Es deliberado: si el gateway reportara caido porque un servicio lo esta, un
 * fallo en publicidad tumbaria el acceso a todo lo demas.
 */
@RestController
public class HealthController {

    private final String version;

    public HealthController(@Value("${wearhack.version:desconocida}") String version) {
        this.version = version;
    }

    @GetMapping("/health")
    public Mono<Estado> health() {
        return Mono.just(new Estado("gateway", "UP", version, Instant.now()));
    }

    /** Respuesta del health check. Misma forma que la de los servicios de negocio. */
    public record Estado(String servicio, String estado, String version, Instant momento) {}
}
