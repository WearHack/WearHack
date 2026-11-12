package com.wearhack.closet.prendas;

import com.wearhack.plataforma.ReglaDeNegocioException;
import java.util.List;

/**
 * El color base de la prenda.
 *
 * @param lab {@code [L, a, b]}, la fuente de verdad
 * @param categoria derivada del Lab, para la interfaz y los filtros
 */
public record ColorPrenda(List<Double> lab, CategoriaColor categoria) {

    public ColorPrenda {
        if (lab == null || lab.size() != 3 || lab.stream().anyMatch(v -> v == null || !Double.isFinite(v))) {
            throw new ReglaDeNegocioException("El color necesita tres valores Lab finitos");
        }
        if (lab.get(0) < 0 || lab.get(0) > 100) {
            throw new ReglaDeNegocioException("La luminosidad L debe estar entre 0 y 100");
        }
        if (categoria == null) {
            throw new ReglaDeNegocioException("El color necesita su categoria");
        }
        lab = List.copyOf(lab);
    }

    public ColorPrenda conCategoria(CategoriaColor nueva) {
        return new ColorPrenda(lab, nueva);
    }
}
