package com.wearhack.closet.colores;

import java.time.Instant;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Un bloque ISCC-NBS cuya categoria cambio por las correcciones de los usuarios (#58).
 *
 * <p>Los centroides no se mueven: son el estandar. Lo que cambia es a que categoria se traduce el
 * bloque. Un bloque sin documento aqui usa la categoria de la tabla.
 *
 * @param bloque numero ISCC-NBS (1 a 267)
 * @param categoria la categoria vigente, con los nombres de {@code CategoriaColor}
 * @param categoriaTabla la que trae la tabla, para revisar el cambio
 * @param correcciones cuantas correcciones del bloque se contaron
 * @param acuerdo fraccion de esas correcciones que pidieron {@code categoria}
 * @param actualizadoEn cuando se decidio; las correcciones anteriores ya no cuentan para el
 *     bloque
 */
@Document(AjusteCategoria.COLECCION)
public record AjusteCategoria(
        @Id Integer bloque,
        String categoria,
        @Field("categoria_tabla") String categoriaTabla,
        int correcciones,
        double acuerdo,
        @Field("actualizado_en") Instant actualizadoEn) {

    public static final String COLECCION = "ajustes_categoria_color";
}
