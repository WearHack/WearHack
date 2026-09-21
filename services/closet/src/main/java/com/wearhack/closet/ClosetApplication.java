package com.wearhack.closet;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Servicio de closet de WearHack.
 *
 * <p>Esqueleto. Arranca, responde /health y emite trazas. Nada mas.
 */
@SpringBootApplication
public class ClosetApplication {

    public static void main(String[] args) {
        SpringApplication.run(ClosetApplication.class, args);
    }
}
