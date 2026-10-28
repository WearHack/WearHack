package com.wearhack.usuarios.colorimetria;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.util.List;

/** Lo que devuelve Colorimetria. cabello e iris pueden faltar: nunca se imputan. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record ResultadoColorimetria(
        String temporada, Double confianza, List<String> ejes, Lab piel, Lab cabello, Lab iris) {}