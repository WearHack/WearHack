package com.wearhack.usuarios.colorimetria;

import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import java.net.http.HttpClient;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Component
class ClienteColorimetriaHttp implements ClienteColorimetria {

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
        } catch (RestClientException e) {
            throw new ServicioIaNoDisponibleException("Colorimetria no respondio", e);
        }
        if (r == null || r.temporada() == null || r.temporada().isBlank() || r.ejes() == null
                || r.piel() == null || r.confianza() == null || r.confianza() < 0 || r.confianza() > 1) {
            throw new ServicioIaNoDisponibleException("Colorimetria devolvio una respuesta invalida", null);
        }
        return r;
    }
}