package com.wearhack.outfits.api;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.wearhack.closet.PrendasParaOutfits.Prenda;
import com.wearhack.closet.PrendasParaOutfits.Rango;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

@Component
class ClienteRecomendador {
    private final RestClient http;

    ClienteRecomendador(@Value("${wearhack.ia.recomendador.url}") String url) {
        var fabrica = new JdkClientHttpRequestFactory(HttpClient.newBuilder()
                .version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(2)).build());
        fabrica.setReadTimeout(Duration.ofSeconds(10));
        http = RestClient.builder().baseUrl(url).requestFactory(fabrica).build();
    }

    List<Combinacion> generar(String usuario, String ocasion, String mood, String clima, Rango rango,
            List<Prenda> prendas) {
        var peticion = new Peticion(usuario, new Contexto(ocasion, mood, clima, rango),
                prendas.stream().map(Candidato::de).toList());
        try {
            var respuesta = http.post().uri("/v1/recomendacion/generar")
                    .contentType(MediaType.APPLICATION_JSON).body(peticion)
                    .retrieve().body(Respuesta.class);
            if (respuesta != null && respuesta.outfits() != null) return respuesta.outfits();
        } catch (RestClientException error) {
            throw new ServicioIaNoDisponibleException("No se pudo consultar el recomendador", error);
        }
        throw new ServicioIaNoDisponibleException("El recomendador no devolvió opciones válidas", null);
    }

    record Peticion(@JsonProperty("usuario_id") String usuario, Contexto contexto, List<Candidato> candidatos) {}

    record Contexto(String ocasion, String mood, String clima,
            @JsonProperty("formalidad_evento") Rango formalidadEvento) {}

    record Candidato(String id, @JsonProperty("slot_outfit") String slot, List<Double> lab, String tipo,
            String textura, String patron, Rango formalidad, @JsonProperty("clima_apto") List<String> climas,
            @JsonProperty("version_esquema") int version) {
        static Candidato de(Prenda p) {
            return new Candidato(p.id(), p.slot(), p.lab(), p.tipo(), p.textura(), p.patron(), p.formalidad(),
                    p.climas(), p.version());
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    record Respuesta(List<Combinacion> outfits) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    record Combinacion(List<String> prendas, double costo) {}
}
