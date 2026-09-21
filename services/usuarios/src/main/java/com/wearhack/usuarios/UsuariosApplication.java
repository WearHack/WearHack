package com.wearhack.usuarios;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Servicio de usuarios de WearHack.
 *
 * <p>Esqueleto. Arranca, responde /health y emite trazas. Nada mas.
 */
@SpringBootApplication
public class UsuariosApplication {

    public static void main(String[] args) {
        SpringApplication.run(UsuariosApplication.class, args);
    }
}
