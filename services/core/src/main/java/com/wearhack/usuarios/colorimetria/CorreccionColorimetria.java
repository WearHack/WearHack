package com.wearhack.usuarios.colorimetria;

import java.time.Instant;
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
 * @param usuarioId {@code null} una vez desvinculada
 * @param creadaEn {@code null} una vez desvinculada
 * @param mes {@code AAAA-MM}; solo existe una vez desvinculada
 */
@Document(DesvinculacionCorrecciones.CORRECCIONES)
public record CorreccionColorimetria(
        @Id String id,
        @Field("usuario_id") String usuarioId,
        Lab piel,
        @Field("temporada_confirmada") String temporadaConfirmada,
        @Field("creada_en") Instant creadaEn,
        String mes) {}
