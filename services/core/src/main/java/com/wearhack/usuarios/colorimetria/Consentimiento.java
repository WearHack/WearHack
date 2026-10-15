package com.wearhack.usuarios.colorimetria;

import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Evidencia de una autorizacion: quien, que version del texto, cuando, para que y en que
 * estado esta (politica de datos, seccion 3).
 *
 * <p>Un consentimiento no se edita ni se borra al revocarlo: cambia de estado. Asi queda la
 * evidencia de que existio y de cuando termino.
 *
 * @param estado {@value #OTORGADO}, {@value #REVOCADO} o {@value #SUSTITUIDO}. Sustituido
 *     es el que se otorgo con una version anterior del texto y quedo reemplazado por otro
 */
@Document("consentimientos")
public record Consentimiento(
        @Id String id,
        @Field("usuario_id") String usuarioId,
        String finalidad,
        @Field("version_texto") String versionTexto,
        String estado,
        @Field("otorgado_en") Instant otorgadoEn,
        @Field("revocado_en") Instant revocadoEn) {

    public static final String OTORGADO = "otorgado";
    public static final String REVOCADO = "revocado";
    public static final String SUSTITUIDO = "sustituido";

    public boolean vigente() {
        return OTORGADO.equals(estado);
    }

    Consentimiento revocado(Instant ahora) {
        return new Consentimiento(id, usuarioId, finalidad, versionTexto, REVOCADO, otorgadoEn, ahora);
    }

    Consentimiento sustituido() {
        return new Consentimiento(id, usuarioId, finalidad, versionTexto, SUSTITUIDO, otorgadoEn, null);
    }
}
