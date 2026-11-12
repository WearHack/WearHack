package com.wearhack.closet.prendas;

import com.wearhack.plataforma.ReglaDeNegocioException;

/** Casi siempre de un solo nivel; abarca dos solo en las prendas versatiles. */
public record RangoFormalidad(Formalidad min, Formalidad max) {

    public RangoFormalidad {
        if (min == null || max == null) {
            throw new ReglaDeNegocioException("La formalidad necesita min y max");
        }
        if (min.compareTo(max) > 0) {
            throw new ReglaDeNegocioException("La formalidad minima no puede ser mayor que la maxima");
        }
    }

    public static RangoFormalidad de(Formalidad nivel) {
        return new RangoFormalidad(nivel, nivel);
    }
}
