package com.wearhack.usuarios.colorimetria;

import static org.assertj.core.api.Assertions.assertThat;

import com.wearhack.MongoDePrueba;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.testcontainers.junit.jupiter.Testcontainers;

/** La tarea de la issue #57, contra un Mongo real: es una actualizacion por pipeline. */
@SpringBootTest
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class DesvinculacionCorreccionesTest {

    private static final Instant AHORA = Instant.parse("2026-10-15T08:30:00Z");

    @Autowired
    private DesvinculacionCorrecciones tarea;

    @Autowired
    private MongoTemplate mongo;

    @BeforeEach
    void limpiar() {
        mongo.getDb().drop();
    }

    @Test
    void sinRecalibracionesSoloDesvinculaLasDeMasDe30Dias() {
        guardar("vieja", hace(31));
        guardar("reciente", hace(29));

        assertThat(tarea.desvincular(AHORA)).isEqualTo(1);

        assertDesvinculada("vieja", "2026-09");
        assertVinculada("reciente");
    }

    @Test
    void desvinculaLasQueConsumioLaRecalibracion() {
        guardar("consumida", hace(5));
        guardar("justo-en-la-marca", hace(3));
        guardar("posterior", hace(1));
        marcarRecalibracion(hace(10));
        marcarRecalibracion(hace(3)); // la mas alta es la que cuenta

        assertThat(tarea.desvincular(AHORA)).isEqualTo(2);

        assertDesvinculada("consumida", "2026-10");
        assertDesvinculada("justo-en-la-marca", "2026-10");
        assertVinculada("posterior");
    }

    @Test
    void unaMarcaEnElFuturoNoAdelantaElCorte() {
        guardar("de-hoy", AHORA);
        guardar("de-manana", AHORA.plus(Duration.ofDays(1)));
        marcarRecalibracion(AHORA.plus(Duration.ofDays(2)));

        assertThat(tarea.desvincular(AHORA)).isEqualTo(1);

        assertDesvinculada("de-hoy", "2026-10");
        assertVinculada("de-manana");
    }

    @Test
    void lasYaDesvinculadasNoSeTocan() {
        guardar("vieja", hace(40));
        tarea.desvincular(AHORA);

        assertThat(tarea.desvincular(AHORA)).isZero();
        assertDesvinculada("vieja", "2026-09");
    }

    @Test
    void laCorreccionConservaLoQueAlimentaLaRecalibracion() {
        guardar("vieja", hace(40));

        tarea.desvincular(AHORA);

        CorreccionColorimetria correccion = mongo.findById("vieja", CorreccionColorimetria.class);
        assertThat(correccion.piel()).isEqualTo(new Lab(61, 13, 18));
        assertThat(correccion.temporadaConfirmada()).isEqualTo("otono_suave");
    }

    @Test
    void desvincularConservaCabelloEIris() {
        mongo.save(new CorreccionColorimetria("completa", "sub-ana", new Lab(61, 13, 18), new Lab(25, 4, 8),
                new Lab(35, 2, 12), "OTONO", hace(40), null));

        tarea.desvincular(AHORA);

        CorreccionColorimetria correccion = mongo.findById("completa", CorreccionColorimetria.class);
        assertThat(correccion.usuarioId()).isNull();
        assertThat(correccion.cabello()).isEqualTo(new Lab(25, 4, 8));
        assertThat(correccion.iris()).isEqualTo(new Lab(35, 2, 12));
    }

    @Test
    void cuentaUsuariosDistintosParaElLogDeLaCorrida() {
        guardar("ana-1", hace(31));
        guardar("ana-2", hace(40));
        mongo.save(new CorreccionColorimetria("beto", "sub-beto", new Lab(50, 10, 10), "verano", hace(35), null));
        guardar("ana-reciente", hace(1));

        assertThat(tarea.usuariosPorDesvincular(AHORA)).isEqualTo(2);
        assertThat(tarea.desvincular(AHORA)).isEqualTo(3);
        assertThat(tarea.usuariosPorDesvincular(AHORA)).isZero();
    }

    private void guardar(String id, Instant creadaEn) {
        mongo.save(new CorreccionColorimetria(id, "sub-ana", new Lab(61, 13, 18), "otono_suave", creadaEn, null));
    }

    private void marcarRecalibracion(Instant correccionesHasta) {
        mongo.insert(new Document("correcciones_hasta", Date.from(correccionesHasta))
                .append("ejecutada_en", Date.from(AHORA)), DesvinculacionCorrecciones.RECALIBRACIONES);
    }

    private static Instant hace(int dias) {
        return AHORA.minus(Duration.ofDays(dias));
    }

    private void assertDesvinculada(String id, String mes) {
        Document documento = crudo(id);
        assertThat(documento).doesNotContainKeys("usuario_id", "creada_en");
        assertThat(documento.getString("mes")).isEqualTo(mes);
    }

    private void assertVinculada(String id) {
        Document documento = crudo(id);
        assertThat(documento.getString("usuario_id")).isEqualTo("sub-ana");
        assertThat(documento).containsKey("creada_en").doesNotContainKey("mes");
    }

    private Document crudo(String id) {
        return mongo.getCollection(DesvinculacionCorrecciones.CORRECCIONES)
                .find(new Document("_id", id))
                .first();
    }
}
