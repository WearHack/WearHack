package com.wearhack.closet.colores;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Los bloques ISCC-NBS que cambiaron de categoria (#58). La app los aplica sobre la tabla que trae
 * para que la categoria que propone siga lo que corrigen los usuarios.
 *
 * <p>Es igual para todos los usuarios: no lleva nada personal. Pide token como el resto del Core.
 */
@RestController
@RequestMapping("/api/v1/closet/colores")
class AjustesColorController {

    private final MongoTemplate mongo;

    AjustesColorController(MongoTemplate mongo) {
        this.mongo = mongo;
    }

    @GetMapping("/ajustes")
    Respuesta ajustes() {
        List<Ajuste> ajustes = mongo.findAll(AjusteCategoria.class).stream()
                .sorted(Comparator.comparing(AjusteCategoria::bloque))
                .map(a -> new Ajuste(a.bloque(), a.categoria(), a.actualizadoEn()))
                .toList();
        return new Respuesta(ajustes);
    }

    record Respuesta(List<Ajuste> ajustes) {}

    /** Desde {@code desde} el bloque se traduce a {@code categoria}. */
    record Ajuste(int bloque, String categoria, Instant desde) {}
}
