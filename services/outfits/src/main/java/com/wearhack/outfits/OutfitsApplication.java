package com.wearhack.outfits;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Servicio de outfits de WearHack.
 *
 * <p>Esqueleto. Arranca, responde /health y emite trazas. Nada mas.
 */
@SpringBootApplication
public class OutfitsApplication {

    public static void main(String[] args) {
        SpringApplication.run(OutfitsApplication.class, args);
    }
}
