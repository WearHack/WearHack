package com.wearhack.gateway;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.test.StepVerifier;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Comprueba que el gateway levanta, que responde sus dos health checks y que
 * las seis rutas quedaron registradas.
 *
 * <p>Sin servidor real ni servicios de abajo: aqui solo interesa que la
 * configuracion de rutas sea valida. Que el ruteo funcione de punta a punta se
 * comprueba en el compose, con los servicios levantados.
 */
@SpringBootTest
@AutoConfigureWebTestClient
class GatewayApplicationTest {

    @Autowired
    private WebTestClient cliente;

    @Autowired
    private RouteLocator rutas;

    @Test
    void elHealthDelGatewayResponde() {
        cliente.get().uri("/health").exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.servicio").isEqualTo("gateway")
                .jsonPath("$.estado").isEqualTo("UP");
    }

    @Test
    void elHealthDeActuatorResponde() {
        cliente.get().uri("/actuator/health").exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.status").isEqualTo("UP");
    }

    @Test
    void estanRegistradasLasSeisRutas() {
        StepVerifier.create(rutas.getRoutes().map(ruta -> ruta.getId()).collectList())
                .assertNext(ids -> assertThat(ids).containsExactlyInAnyOrder(
                        "usuarios", "closet", "outfits", "publicidad",
                        "colorimetria", "recomendador"))
                .verifyComplete();
    }
}
