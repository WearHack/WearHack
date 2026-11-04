package com.wearhack.publicidad;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.MongoDePrueba;
import com.wearhack.publicidad.puentes.RankingPrendaPuente;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Publicidad lee el ranking que deja el job (issue #38). Los documentos se insertan crudos,
 * con el esquema del job de Python, para que un cambio de nombre de campo se note aqui.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class PuentesTest {

    private static final String SUB = "sub-puentes-test";
    private static final Instant CALCULADO = Instant.parse("2026-11-01T08:00:00Z");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MongoTemplate mongo;

    @BeforeEach
    void limpiar() {
        mongo.dropCollection(RankingPrendaPuente.COLECCION);
    }

    @Test
    void sinTokenResponde401() throws Exception {
        mockMvc.perform(get("/api/v1/publicidad/me/puentes"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void devuelveLasPuentesEnElOrdenDelJob() throws Exception {
        mongo.insert(new Document("_id", SUB)
                .append("puentes", List.of(
                        puente("cat-1", 7, 2, 0.31),
                        puente("cat-2", 5, 0, null)))
                .append("umbral", 3)
                .append("calculado_en", Date.from(CALCULADO)), RankingPrendaPuente.COLECCION);

        mockMvc.perform(get("/api/v1/publicidad/me/puentes").with(usuario(SUB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.puentes.length()").value(2))
                .andExpect(jsonPath("$.puentes[0].prendaId").value("cat-1"))
                .andExpect(jsonPath("$.puentes[0].combinacionesBuenas").value(7))
                .andExpect(jsonPath("$.puentes[0].eventosNuevos").value(2))
                .andExpect(jsonPath("$.puentes[0].costoMedio").value(0.31))
                .andExpect(jsonPath("$.puentes[1].prendaId").value("cat-2"))
                .andExpect(jsonPath("$.calculadoEn").value("2026-11-01T08:00:00Z"));
    }

    @Test
    void soloVeElSuyo() throws Exception {
        mongo.insert(new Document("_id", "otro-sub")
                .append("puentes", List.of(puente("cat-9", 4, 1, 0.5)))
                .append("calculado_en", Date.from(CALCULADO)), RankingPrendaPuente.COLECCION);

        mockMvc.perform(get("/api/v1/publicidad/me/puentes").with(usuario(SUB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.puentes.length()").value(0));
    }

    @Test
    void sinRankingTodaviaDevuelveListaVacia() throws Exception {
        mockMvc.perform(get("/api/v1/publicidad/me/puentes").with(usuario(SUB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.puentes.length()").value(0))
                .andExpect(jsonPath("$.calculadoEn").isEmpty());
    }

    private static Document puente(String prendaId, int buenas, int eventos, Double costo) {
        return new Document("prenda_id", prendaId)
                .append("combinaciones_buenas", buenas)
                .append("eventos_nuevos", eventos)
                .append("costo_medio", costo);
    }

    private static RequestPostProcessor usuario(String sub) {
        return jwt().jwt(token -> token.subject(sub));
    }
}
