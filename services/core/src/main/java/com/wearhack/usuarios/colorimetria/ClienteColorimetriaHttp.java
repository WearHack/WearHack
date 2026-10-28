package com.wearhack.usuarios.colorimetria;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

@Component
class ClienteColorimetriaHttp implements ClienteColorimetria {

    static final String RECORTE_INVALIDO = "No se pudo analizar el recorte: repite la foto";
    // El motivo de Colorimetria se reenvia al usuario; acotado por si un dia trae mas de la cuenta.
    private static final int LARGO_MAXIMO_MOTIVO = 200;

    private final RestClient http;
    private final String ruta;

    ClienteColorimetriaHttp(
            @Value("${wearhack.ia.colorimetria.url}") String url,
            @Value("${wearhack.ia.colorimetria.ruta}") String ruta,
            @Value("${wearhack.ia.colorimetria.timeout-segundos}") long timeoutSegundos) {
        HttpClient cliente = HttpClient.newBuilder()
                .version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(2))
                .build();
        JdkClientHttpRequestFactory fabrica = new JdkClientHttpRequestFactory(cliente);
        fabrica.setReadTimeout(Duration.ofSeconds(timeoutSegundos));
        this.http = RestClient.builder().baseUrl(url).requestFactory(fabrica).build();
        this.ruta = ruta;
    }

    @Override
    public ResultadoColorimetria analizar(byte[] recortePng) {
        ResultadoColorimetria r;
        try {
            r = http.post().uri(ruta).contentType(MediaType.IMAGE_PNG).body(recortePng)
                    .retrieve().body(ResultadoColorimetria.class);
        } catch (RestClientResponseException e) {
            // 422 es el recorte (sin rostro, sin piel): el usuario puede repetir la foto. Como
            // 503 le diria que el servicio esta caido y que vuelva mas tarde, que no sirve de nada.
            if (e.getStatusCode().isSameCodeAs(HttpStatus.UNPROCESSABLE_CONTENT)) {
                throw new ReglaDeNegocioException(mensajeRecorteInvalido(e));
            }
            throw new ServicioIaNoDisponibleException(
                    "Colorimetria respondio " + e.getStatusCode().value(), e);
        } catch (RestClientException e) {
            throw new ServicioIaNoDisponibleException("Colorimetria no respondio", e);
        }
        if (r == null || r.temporada() == null || r.temporada().isBlank() || r.ejes() == null
                || r.piel() == null || r.confianza() == null || r.confianza() < 0 || r.confianza() > 1) {
            throw new ServicioIaNoDisponibleException("Colorimetria devolvio una respuesta invalida", null);
        }
        return r;
    }

    private static String mensajeRecorteInvalido(RestClientResponseException e) {
        String motivo = null;
        try {
            DetalleError detalle = e.getResponseBodyAs(DetalleError.class);
            motivo = detalle == null ? null : detalle.detail();
        } catch (RuntimeException ilegible) {
            // Sin motivo legible, el mensaje general basta.
        }
        if (motivo == null || motivo.isBlank()) {
            return RECORTE_INVALIDO;
        }
        motivo = motivo.strip();
        if (motivo.length() > LARGO_MAXIMO_MOTIVO) {
            motivo = motivo.substring(0, LARGO_MAXIMO_MOTIVO);
        }
        return RECORTE_INVALIDO + ". " + motivo;
    }

    /** El cuerpo de error de FastAPI: {"detail": "..."}. */
    @JsonIgnoreProperties(ignoreUnknown = true)
    record DetalleError(String detail) {}
}
