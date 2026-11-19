package com.wearhack.closet.colores;

import static net.logstash.logback.argument.StructuredArguments.kv;

import com.wearhack.closet.prendas.CorreccionClasificacion;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Tarea programada que ajusta la categoria de los bloques ISCC-NBS con las correcciones de los
 * usuarios (#58, respuestas C.15 y G.41).
 *
 * <p>Cada correccion de {@code correcciones_clasificacion} (el Lab medido y la categoria que eligio
 * el usuario) se asigna a su bloque con ΔE00, igual que en la app. Si un bloque junta
 * {@value #MINIMO_CORRECCIONES} correcciones o mas y al menos el 70 % pide la misma categoria,
 * distinta de la vigente, el bloque pasa a esa categoria. El cambio queda en
 * {@code ajustes_categoria_color} con los conteos, para revisarlo, y la app lo baja de
 * {@code GET /api/v1/closet/colores/ajustes}.
 *
 * <p>Tras un cambio, para ese bloque solo cuentan las correcciones posteriores: las de antes ya se
 * usaron para decidirlo.
 *
 * <p>Solo lee {@code correcciones_clasificacion}; no la modifica.
 */
@Component
class AjusteCategoriasColor {

    static final int MINIMO_CORRECCIONES = 10;
    static final double ACUERDO_MINIMO = 0.70;

    private static final Logger log = LoggerFactory.getLogger(AjusteCategoriasColor.class);

    private final MongoTemplate mongo;
    private final TablaIsccNbs tabla;
    private final Clock reloj;

    AjusteCategoriasColor(MongoTemplate mongo, TablaIsccNbs tabla, Clock reloj) {
        this.mongo = mongo;
        this.tabla = tabla;
        this.reloj = reloj;
    }

    /** Una vez al dia, despues de la desvinculacion de correcciones. "-" la desactiva. */
    @Scheduled(cron = "${wearhack.closet.colores.ajuste-cron:0 0 9 * * *}", zone = "UTC")
    void programada() {
        Instant ahora = Instant.now(reloj);
        List<AjusteCategoria> cambios = ajustar(ahora);
        // La misma linea de corrida que los jobs de Python (#50).
        log.info("Bloques ISCC-NBS que cambiaron de categoria: {}", cambios.size(),
                kv("job", "ajuste_categorias_color"),
                kv("estado", "termina"),
                kv("umbral_alcanzado", !cambios.isEmpty()),
                kv("bloques", cambios.stream().map(AjusteCategoria::bloque).toList()),
                kv("timestamp", ahora.toString()));
    }

    /** @return los bloques que cambiaron en esta corrida */
    List<AjusteCategoria> ajustar(Instant ahora) {
        Map<Integer, AjusteCategoria> vigentes = mongo.findAll(AjusteCategoria.class).stream()
                .collect(Collectors.toMap(AjusteCategoria::bloque, Function.identity()));

        Map<Integer, List<String>> porBloque = new HashMap<>();
        try (Stream<CorreccionClasificacion> correcciones =
                mongo.stream(new Query(), CorreccionClasificacion.class)) {
            correcciones.forEach(c -> {
                if (c.lab() == null || c.lab().size() != 3 || c.categoriaConfirmada() == null) {
                    return;
                }
                int bloque = tabla.masCercano(c.lab().get(0), c.lab().get(1), c.lab().get(2)).numero();
                AjusteCategoria vigente = vigentes.get(bloque);
                if (vigente != null && c.creadoEn() != null
                        && !c.creadoEn().isAfter(vigente.actualizadoEn())) {
                    return;
                }
                porBloque.computeIfAbsent(bloque, b -> new ArrayList<>())
                        .add(c.categoriaConfirmada().name());
            });
        }

        List<AjusteCategoria> cambios = new ArrayList<>();
        porBloque.forEach((bloque, categorias) -> {
            String tablaDice = tabla.bloque(bloque).categoria();
            AjusteCategoria vigente = vigentes.get(bloque);
            String actual = vigente != null ? vigente.categoria() : tablaDice;
            decidir(categorias, actual).ifPresent(d -> {
                AjusteCategoria cambio = new AjusteCategoria(
                        bloque, d.categoria(), tablaDice, d.correcciones(), d.acuerdo(), ahora);
                mongo.save(cambio);
                cambios.add(cambio);
            });
        });
        return cambios;
    }

    /** Lo que se decidio para un bloque. */
    record Decision(String categoria, int correcciones, double acuerdo) {}

    /**
     * La regla, sin Mongo: {@value #MINIMO_CORRECCIONES} correcciones o mas, y al menos el 70 % por
     * una misma categoria distinta de la {@code actual}.
     */
    static Optional<Decision> decidir(List<String> categorias, String actual) {
        int total = categorias.size();
        if (total < MINIMO_CORRECCIONES) {
            return Optional.empty();
        }
        return categorias.stream()
                .collect(Collectors.groupingBy(Function.identity(), Collectors.counting()))
                .entrySet().stream()
                .max(Map.Entry.comparingByValue())
                .filter(e -> !e.getKey().equals(actual))
                .filter(e -> e.getValue() >= Math.ceil(ACUERDO_MINIMO * total - 1e-9))
                .map(e -> new Decision(e.getKey(), total, e.getValue() / (double) total));
    }
}
