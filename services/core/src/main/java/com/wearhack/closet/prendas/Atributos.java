package com.wearhack.closet.prendas;

import java.util.List;
import org.springframework.data.mongodb.core.mapping.Field;

/**
 * Lo que se sabe de una prenda. {@code clima_apto} va aqui y no en la raiz porque asi esta
 * definido el indice ESR ({@code usuario_id + slot_outfit + atributos.clima_apto}).
 *
 * @param subtipoCalzado solo en calzado
 * @param textura {@code null} en calzado y accesorios
 * @param formalidad {@code null} en los accesorios neutros, que no entran al filtro de dress code
 */
public record Atributos(
        Tipo tipo,
        @Field("subtipo_calzado") SubtipoCalzado subtipoCalzado,
        Patron patron,
        Textura textura,
        RangoFormalidad formalidad,
        @Field("clima_apto") List<Clima> climaApto,
        ColorPrenda color) {}
