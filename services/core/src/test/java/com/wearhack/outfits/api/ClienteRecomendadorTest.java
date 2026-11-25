package com.wearhack.outfits.api;

import static org.assertj.core.api.Assertions.assertThat;

import com.sun.net.httpserver.HttpServer;
import com.wearhack.closet.PrendasParaOutfits.Prenda;
import com.wearhack.closet.PrendasParaOutfits.Rango;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

class ClienteRecomendadorTest {
    @Test
    void enviaJsonSinPedirUnaActualizacionDeProtocolo() throws Exception {
        var servidor = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        try {
            var upgrade = new AtomicReference<String>();
            var tipo = new AtomicReference<String>();
            var cuerpo = new AtomicReference<String>();
            servidor.createContext("/v1/recomendacion/generar", peticion -> {
                try (peticion) {
                    upgrade.set(peticion.getRequestHeaders().getFirst("Upgrade"));
                    tipo.set(peticion.getRequestHeaders().getFirst("Content-Type"));
                    cuerpo.set(new String(peticion.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
                    byte[] json = "{\"outfits\":[{\"prendas\":[\"zapato\"],\"costo\":0.2}]}"
                            .getBytes(StandardCharsets.UTF_8);
                    peticion.getResponseHeaders().set("Content-Type", "application/json");
                    peticion.sendResponseHeaders(200, json.length);
                    peticion.getResponseBody().write(json);
                }
            });
            servidor.start();
            var cliente = new ClienteRecomendador("http://127.0.0.1:" + servidor.getAddress().getPort());
            var rango = new Rango("CASUAL", "SMART_CASUAL");
            var prendas = List.of(new Prenda("zapato", "CALZADO", List.of(30.0, 0.0, 0.0),
                    "CALZADO", null, "LISO", rango, List.of("TEMPLADO"), 1, Instant.EPOCH));

            assertThat(cliente.generar("prueba", "DIA_A_DIA", null, null, rango, prendas))
                    .containsExactly(new ClienteRecomendador.Combinacion(List.of("zapato"), 0.2));
            assertThat(upgrade.get()).isNull();
            assertThat(tipo.get()).startsWith("application/json");
            assertThat(cuerpo.get()).contains("\"usuario_id\":\"prueba\"", "\"slot_outfit\":\"CALZADO\"",
                    "\"formalidad_evento\":", "\"clima_apto\":[\"TEMPLADO\"]");
        } finally {
            servidor.stop(0);
        }
    }
}
