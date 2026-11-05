package com.wearhack.usuarios.colorimetria;

import java.time.Instant;
import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Una correccion del usuario a su temporada: alimenta la recalibracion de centroides.
 *
 * <p>Nace vinculada al usuario. Despues de consumirla la recalibracion, o a los 30 dias
 * como mucho, {@link DesvinculacionCorrecciones} le quita {@code usuario_id} y reduce
 * {@code creada_en} a {@code mes}: queda como dato agregado.
 *
 * <p>Lleva los colores medidos del perfil, no solo la piel: la recalibracion mueve solo los
 * ejes que la correccion midio, y sin cabello ni iris la capa de contraste no se mueve.
 *
 * @param cabello {@code null} si el perfil no lo midio (sin cabello visible)
 * @param iris {@code null} si el perfil no lo midio
 * @param temporadaConfirmada una de {@link #TEMPORADAS}
 * @param usuarioId {@code null} una vez desvinculada
 * @param creadaEn {@code null} una vez desvinculada
 * @param mes {@code AAAA-MM}; solo existe una vez desvinculada
 */
@Document(DesvinculacionCorrecciones.CORRECCIONES)
public record CorreccionColorimetria(
        @Id String id,
        @Field("usuario_id") String usuarioId,
        Lab piel,
        Lab cabello,
        Lab iris,
        @Field("temporada_confirmada") String temporadaConfirmada,
        @Field("creada_en") Instant creadaEn,
        String mes) {

    /** Las mismas que devuelve el servicio de Colorimetria. Es lo que entiende la recalibracion. */
    public static final List<String> TEMPORADAS = List.of("PRIMAVERA", "VERANO", "OTONO", "INVIERNO");

    /** Una correccion que solo midio la piel, como las anteriores a guardar cabello e iris. */
    public CorreccionColorimetria(String id, String usuarioId, Lab piel, String temporadaConfirmada,
            Instant creadaEn, String mes) {
        this(id, usuarioId, piel, null, null, temporadaConfirmada, creadaEn, mes);
    }
}
