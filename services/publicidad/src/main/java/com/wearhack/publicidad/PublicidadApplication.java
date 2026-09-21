package com.wearhack.publicidad;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Servicio de publicidad de WearHack.
 *
 * <p>Esqueleto. Arranca, responde /health y emite trazas. Nada mas.
 */
@SpringBootApplication
public class PublicidadApplication {

    public static void main(String[] args) {
        SpringApplication.run(PublicidadApplication.class, args);
    }
}
