package com.wearhack.usuarios.colorimetria;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.sun.net.httpserver.HttpServer;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * El cliente contra un servidor HTTP de verdad (el del JDK), para probar como traduce cada
 * respuesta de Colorimetria sin levantar el contexto de Spring.
 */
class ClienteColorimetriaHttpTest {

    private static final String RUTA = "/v1/colorimetria/analizar";
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1};

    private HttpServer servidor;

    @AfterEach
    void parar() {
        if (servidor != null) {
            servidor.stop(0);
        }
    }

    private ClienteColorimetriaHttp responde(int estado, String cuerpo) throws IOException {
        servidor = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        servidor.createContext(RUTA, intercambio -> {
            intercambio.getRequestBody().readAllBytes();
            byte[] bytes = cuerpo.getBytes(StandardCharsets.UTF_8);
            intercambio.getResponseHeaders().add("Content-Type", "application/json");
            intercambio.sendResponseHeaders(estado, bytes.length == 0 ? -1 : bytes.length);
            if (bytes.length > 0) {
                intercambio.getResponseBody().write(bytes);
            }
            intercambio.close();
        });
        servidor.start();
        return new ClienteColorimetriaHttp(
                "http://127.0.0.1:" + servidor.getAddress().getPort(), RUTA, 5);
    }

    @Test
    void unRecorteSinRostroEsUnErrorDelUsuarioConSuMotivo() throws IOException {
        var cliente = responde(422, "{\"detail\": \"No se detecto un rostro en el recorte\"}");

        assertThatThrownBy(() -> cliente.analizar(PNG))
                .isInstanceOf(ReglaDeNegocioException.class)
                .hasMessage(ClienteColorimetriaHttp.RECORTE_INVALIDO
                        + ". No se detecto un rostro en el recorte");
    }

    @Test
    void un422SinMotivoLegibleDaElMensajeGeneral() throws IOException {
        var cliente = responde(422, "no es json");

        assertThatThrownBy(() -> cliente.analizar(PNG))
                .isInstanceOf(ReglaDeNegocioException.class)
                .hasMessage(ClienteColorimetriaHttp.RECORTE_INVALIDO);
    }

    @Test
    void unMotivoLargoSeRecorta() throws IOException {
        var cliente = responde(422, "{\"detail\": \"" + "x".repeat(500) + "\"}");

        assertThatThrownBy(() -> cliente.analizar(PNG))
                .isInstanceOf(ReglaDeNegocioException.class)
                .satisfies(e -> assertThat(e.getMessage())
                        .hasSize(ClienteColorimetriaHttp.RECORTE_INVALIDO.length() + 2 + 200));
    }

    @Test
    void sinCentroidesSigueSiendoNoDisponible() throws IOException {
        var cliente = responde(503, "{\"detail\": \"No hay centroides vigentes publicados\"}");

        assertThatThrownBy(() -> cliente.analizar(PNG))
                .isInstanceOf(ServicioIaNoDisponibleException.class);
    }

    @Test
    void otroErrorDelClienteNoSeLeCulpaAlUsuario() throws IOException {
        // Un 413 o un 400 es un fallo nuestro al llamar, no algo que el usuario pueda arreglar.
        var cliente = responde(413, "{\"detail\": \"El recorte es demasiado grande\"}");

        assertThatThrownBy(() -> cliente.analizar(PNG))
                .isInstanceOf(ServicioIaNoDisponibleException.class);
    }

    @Test
    void unaRespuestaValidaSeDevuelve() throws IOException {
        var cliente = responde(200, """
                {"temporada": "OTONO", "confianza": 0.61, "ejes": ["piel_L"],
                 "piel": {"l": 57.1, "a": 19.0, "b": 23.7}, "cabello": null, "iris": null,
                 "segunda_opcion": "PRIMAVERA", "version_centroides": "4-estaciones-v1"}
                """);

        ResultadoColorimetria r = cliente.analizar(PNG);

        assertThat(r.temporada()).isEqualTo("OTONO");
        assertThat(r.piel()).isEqualTo(new Lab(57.1, 19.0, 23.7));
        assertThat(r.cabello()).isNull();
    }
}
