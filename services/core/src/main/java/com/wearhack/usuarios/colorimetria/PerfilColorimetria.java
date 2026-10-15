package com.wearhack.usuarios.colorimetria;

import java.time.Instant;
import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Los valores derivados del recorte facial. El recorte nunca se guarda: solo esto.
 *
 * <p>Es opcional (un usuario sin perfil es valido) y se trata como dato sensible: se borra
 * al revocar el consentimiento, a peticion del usuario o al eliminar la cuenta.
 *
 * @param usuarioId el {@code sub} de Cognito. Uno por usuario
 * @param ejes los ejes de la clasificacion que se usaron (subtono, valor, croma...)
 * @param confianza de 0 a 1
 */
@Document("perfiles_colorimetria")
public record PerfilColorimetria(
        @Id String usuarioId,
        Lab piel,
        Lab cabello,
        Lab iris,
        List<String> ejes,
        String temporada,
        Double confianza,
        @Field("calculado_en") Instant calculadoEn) {}
