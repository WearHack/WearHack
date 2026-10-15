package com.wearhack.plataforma.config;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Infraestructura comun del Core.
 *
 * <p>Las tareas programadas corren dentro del Core, no como jobs batch aparte. En el lab
 * hay una sola instancia; con varias replicas cada tarea necesitaria un bloqueo para
 * correr una sola vez.
 */
@Configuration
@EnableScheduling
class PlataformaConfig {

    /** Reloj inyectable: las reglas con plazos se prueban sin esperar a que pasen. */
    @Bean
    Clock reloj() {
        return Clock.systemUTC();
    }
}
