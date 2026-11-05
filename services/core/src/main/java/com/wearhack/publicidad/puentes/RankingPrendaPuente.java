package com.wearhack.publicidad.puentes;

import java.time.Instant;
import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Las prendas puente de un usuario, ya ordenadas. Lo escribe el job
 * {@code ranking_prendas_puente} del Recomendador; Publicidad solo lo lee (issue #38).
 *
 * @param usuarioId el {@code sub} de Cognito. Uno por usuario
 * @param umbral las combinaciones buenas que pedia el job para contar una puente
 */
@Document(RankingPrendaPuente.COLECCION)
public record RankingPrendaPuente(
        @Id String usuarioId,
        List<Puente> puentes,
        Integer umbral,
        @Field("calculado_en") Instant calculadoEn) {

    public static final String COLECCION = "ranking_prenda_puente";

    /**
     * @param prendaId la prenda del catalogo ({@code catalogos_marcas})
     * @param eventosNuevos eventos que el usuario no podia cubrir y con ella si
     * @param costoMedio {@code null} si el job no lo pudo calcular
     */
    public record Puente(
            @Field("prenda_id") String prendaId,
            @Field("combinaciones_buenas") int combinacionesBuenas,
            @Field("eventos_nuevos") int eventosNuevos,
            @Field("costo_medio") Double costoMedio) {}
}
