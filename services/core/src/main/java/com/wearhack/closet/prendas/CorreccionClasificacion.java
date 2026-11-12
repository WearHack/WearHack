package com.wearhack.closet.prendas;

import java.time.Instant;
import java.util.List;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * El usuario dijo que el color de una prenda es de otra categoria. Sirve para recalibrar las
 * fronteras de las categorias.
 *
 * <p>Sin {@code usuario_id} ni imagen: solo el Lab medido y la categoria buena. Es lo que
 * hace falta para recalibrar, y asi no es un dato personal.
 */
@Document(CorreccionClasificacion.COLECCION)
public record CorreccionClasificacion(
        @Id String id,
        List<Double> lab,
        @Field("categoria_confirmada") CategoriaColor categoriaConfirmada,
        @Field("creado_en") Instant creadoEn) {

    public static final String COLECCION = "correcciones_clasificacion";
}
