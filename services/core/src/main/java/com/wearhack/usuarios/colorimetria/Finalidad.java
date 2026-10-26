package com.wearhack.usuarios.colorimetria;

import com.wearhack.plataforma.RecursoNoEncontradoException;
import java.util.Arrays;

/**
 * Para que se autoriza un tratamiento. Cada finalidad lleva su propio consentimiento: una
 * autorizacion general no basta (politica de datos, seccion 2).
 */
public enum Finalidad {

    /** Calcular la temporada de color y personalizar los outfits. */
    COLORIMETRIA("colorimetria");

    private final String valor;

    Finalidad(String valor) {
        this.valor = valor;
    }

    /** Como se guarda en Mongo y como viaja por la API. */
    public String valor() {
        return valor;
    }

    public static Finalidad desde(String valor) {
        return Arrays.stream(values())
                .filter(finalidad -> finalidad.valor.equals(valor))
                .findFirst()
                .orElseThrow(() -> new RecursoNoEncontradoException("Finalidad desconocida: " + valor));
    }
}
