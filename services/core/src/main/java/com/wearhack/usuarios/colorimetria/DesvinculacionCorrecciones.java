package com.wearhack.usuarios.colorimetria;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import org.bson.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.AggregationUpdate;
import org.springframework.data.mongodb.core.aggregation.DateOperators;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Desvincula del usuario las correcciones de colorimetria (politica de datos, seccion 7).
 *
 * <p>A una correccion desvinculada se le quita {@code usuario_id} y su {@code creada_en}
 * se reduce a {@code mes} ({@code AAAA-MM}). Se desvinculan:
 *
 * <ul>
 *   <li>las que ya consumio la recalibracion de centroides, segun su marca, y
 *   <li>las que llevan vinculadas mas de {@code dias-maximos} (30), consumidas o no.
 * </ul>
 *
 * <p><strong>Contrato con el job de recalibracion.</strong> La coleccion
 * {@value #RECALIBRACIONES} es del job; aqui solo se lee. Cada corrida deja un documento
 * con {@code correcciones_hasta} (fecha): consumio todas las correcciones con
 * {@code creada_en} menor o igual. Se usa la marca mas alta.
 *
 * <p>Pendiente de validacion legal, igual que la politica que la origina.
 */
@Component
class DesvinculacionCorrecciones {

    static final String CORRECCIONES = "correcciones_colorimetria";
    static final String RECALIBRACIONES = "recalibraciones";

    private static final Logger log = LoggerFactory.getLogger(DesvinculacionCorrecciones.class);

    private final MongoTemplate mongo;
    private final Clock reloj;
    private final Duration plazoMaximo;

    DesvinculacionCorrecciones(
            MongoTemplate mongo,
            Clock reloj,
            @Value("${wearhack.usuarios.correcciones.dias-maximos:30}") int diasMaximos) {
        this.mongo = mongo;
        this.reloj = reloj;
        this.plazoMaximo = Duration.ofDays(diasMaximos);
    }

    @Scheduled(cron = "${wearhack.usuarios.correcciones.cron:0 30 8 * * *}", zone = "UTC")
    void programada() {
        long desvinculadas = desvincular(Instant.now(reloj));
        log.info("Correcciones de colorimetria desvinculadas: {}", desvinculadas);
    }

    /**
     * Una sola actualizacion en Mongo: el mes sale de la propia {@code creada_en} de cada
     * documento, asi que no hace falta leerlos uno a uno.
     *
     * @return cuantas correcciones se desvincularon
     */
    long desvincular(Instant ahora) {
        Instant corte = ahora.minus(plazoMaximo);
        Instant consumidasHasta = marcaDeRecalibracion();
        if (consumidasHasta != null && consumidasHasta.isAfter(corte)) {
            // Una marca en el futuro no puede haber consumido lo que aun no existe.
            corte = consumidasHasta.isAfter(ahora) ? ahora : consumidasHasta;
        }

        // exists y no ne(null): asi la consulta encaja con el indice parcial del init de Mongo.
        // Spring Data no escribe los campos null, asi que una vinculada siempre lo tiene.
        Query vinculadasHastaElCorte = new Query(Criteria.where("usuario_id").exists(true)
                .and("creada_en").lte(Date.from(corte)));
        AggregationUpdate desvincular = AggregationUpdate.update()
                .set("mes").toValue(DateOperators.dateOf("creada_en").toString("%Y-%m"))
                .unset("usuario_id", "creada_en");

        return mongo.updateMulti(vinculadasHastaElCorte, desvincular, CORRECCIONES).getModifiedCount();
    }

    private Instant marcaDeRecalibracion() {
        Query ultima = new Query(Criteria.where("correcciones_hasta").type(9))
                .with(Sort.by(Sort.Direction.DESC, "correcciones_hasta"))
                .limit(1);
        ultima.fields().include("correcciones_hasta");
        Document marca = mongo.findOne(ultima, Document.class, RECALIBRACIONES);
        return marca == null ? null : marca.getDate("correcciones_hasta").toInstant();
    }
}
