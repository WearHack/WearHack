package com.wearhack.usuarios.colorimetria;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.MongoDePrueba;
import java.time.Instant;
import java.util.List;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.junit.jupiter.Testcontainers;

/** El endpoint que registra correcciones de temporada (issue #37). */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class CorreccionesColorimetriaTest {

    private static final String SUB = "sub-correcciones-test";
    private static final String RUTA = "/api/v1/usuarios/me/colorimetria/correcciones";

    private static final Lab PIEL = new Lab(62.1, 14.3, 18.9);
    private static final Lab CABELLO = new Lab(25.0, 4.1, 8.2);
    private static final Lab IRIS = new Lab(35.5, 2.0, 12.4);

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MongoTemplate mongo;

    @BeforeEach
    void limpiar() {
        mongo.getDb().drop();
    }

    @Test
    void sinTokenResponde401() throws Exception {
        mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON).content("{\"temporada\":\"OTONO\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void guardaLaTemporadaConLosColoresDelPerfil() throws Exception {
        otorgarConsentimiento();
        guardarPerfil(CABELLO);

        corregir("otono")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.temporadaConfirmada").value("OTONO"))
                .andExpect(jsonPath("$.creadaEn").isNotEmpty());

        List<Document> guardadas = mongo.getCollection(DesvinculacionCorrecciones.CORRECCIONES)
                .find().into(new java.util.ArrayList<>());
        assertThat(guardadas).hasSize(1);
        Document correccion = guardadas.get(0);
        assertThat(correccion.getString("usuario_id")).isEqualTo(SUB);
        assertThat(correccion.getString("temporada_confirmada")).isEqualTo("OTONO");
        assertThat(correccion.get("piel", Document.class).getDouble("l")).isEqualTo(62.1);
        assertThat(correccion.get("cabello", Document.class).getDouble("l")).isEqualTo(25.0);
        assertThat(correccion.get("iris", Document.class).getDouble("b")).isEqualTo(12.4);
        assertThat(correccion).containsKey("creada_en");
    }

    @Test
    void sinCabelloEnElPerfilLaCorreccionTampocoLoLleva() throws Exception {
        otorgarConsentimiento();
        guardarPerfil(null);

        corregir("VERANO").andExpect(status().isCreated());

        Document correccion = mongo.getCollection(DesvinculacionCorrecciones.CORRECCIONES).find().first();
        assertThat(correccion.get("cabello")).isNull();
        assertThat(correccion.get("iris", Document.class)).isNotNull();
    }

    @Test
    void temporadaDesconocidaResponde422() throws Exception {
        otorgarConsentimiento();
        guardarPerfil(CABELLO);

        corregir("otono_suave").andExpect(status().isUnprocessableContent());
        assertThat(mongo.getCollection(DesvinculacionCorrecciones.CORRECCIONES).countDocuments()).isZero();
    }

    @Test
    void sinConsentimientoResponde422() throws Exception {
        guardarPerfil(CABELLO);

        corregir("INVIERNO").andExpect(status().isUnprocessableContent());
    }

    @Test
    void sinPerfilResponde404() throws Exception {
        otorgarConsentimiento();

        corregir("INVIERNO").andExpect(status().isNotFound());
    }

    private ResultActions corregir(String temporada) throws Exception {
        return mockMvc.perform(post(RUTA)
                .with(jwt().jwt(token -> token.subject(SUB)))
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"temporada\":\"" + temporada + "\"}"));
    }

    private void otorgarConsentimiento() {
        mongo.save(new Consentimiento("c-1", SUB, Finalidad.COLORIMETRIA.valor(), "v1",
                Consentimiento.OTORGADO, Instant.parse("2026-11-01T00:00:00Z"), null));
    }

    private void guardarPerfil(Lab cabello) {
        mongo.save(new PerfilColorimetria(SUB, PIEL, cabello, IRIS, List.of("subtono", "contraste"),
                "PRIMAVERA", 0.7, Instant.parse("2026-11-01T00:00:00Z")));
    }
}
