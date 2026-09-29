package com.wearhack.plataforma.api;

import com.wearhack.plataforma.Estado;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Health del Core entero.
 *
 * <p>Responde si el proceso esta en pie. No mira a los servicios de IA: si el Core
 * reportara caido porque la IA lo esta, un fallo de la IA tumbaria el acceso a todo
 * lo demas, y la degradacion controlada es justo lo contrario. El estado de la IA se
 * consulta aparte, en {@code /actuator/health/ia}.
 */
@RestController
public class CoreHealthController {

    private final String version;

    public CoreHealthController(@Value("${wearhack.version:desconocida}") String version) {
        this.version = version;
    }

    @GetMapping("/health")
    public Estado health() {
        return Estado.arriba(version);
    }
}
