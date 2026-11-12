package com.wearhack.closet.prendas;

import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Una prenda del closet. La imagen (ya sin fondo) vive en S3; aqui solo su clave.
 *
 * @param id lo genera el dispositivo, para que reintentar la subida no la duplique
 * @param usuarioId el {@code sub} de Cognito
 */
@Document(Prenda.COLECCION)
public record Prenda(
        @Id String id,
        @Field("usuario_id") String usuarioId,
        @Field("slot_outfit") SlotOutfit slotOutfit,
        Atributos atributos,
        @Field("imagen_key") String imagenKey,
        @Field("version_esquema") int versionEsquema,
        @Field("creado_en") Instant creadoEn,
        @Field("actualizado_en") Instant actualizadoEn) {

    public static final String COLECCION = "prendas";
    public static final int VERSION_ESQUEMA = 1;
}
