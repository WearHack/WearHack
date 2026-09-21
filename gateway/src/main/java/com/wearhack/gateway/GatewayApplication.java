package com.wearhack.gateway;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Entrada unica a WearHack: ruteo, autenticacion y control de acceso.
 *
 * <p>Esqueleto. Rutea, responde /health y emite trazas. La autenticacion es un
 * stub que deja pasar todo; ver {@link com.wearhack.gateway.seguridad.AutenticacionGlobalFilter}.
 */
@SpringBootApplication
public class GatewayApplication {

    public static void main(String[] args) {
        SpringApplication.run(GatewayApplication.class, args);
    }
}
