package com.wearhack.closet.colores;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.MongoDePrueba;
import com.wearhack.closet.prendas.CategoriaColor;
import com.wearhack.closet.prendas.CorreccionClasificacion;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.junit.jupiter.Testcontainers;

/** La tarea y el endpoint contra un Mongo real (#58). */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class AjustesColorMongoTest {

    private static final String RUTA = "/api/v1/closet/colores/ajustes";
    /** Centroide de "strong red" (bloque 12), que la tabla traduce a ROJO. */
    private static final List<Double> ROJO_FUERTE = List.of(45.75, 53.81, 22.02);
    private static final Instant ANTES = Instant.parse("2026-11-01T00:00:00Z");
    private static final Instant AHORA = Instant.parse("2026-11-19T09:00:00Z");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MongoTemplate mongo;

    @Autowired
    private AjusteCategoriasColor tarea;

    @BeforeEach
    void limpiar() {
        mongo.dropCollection(CorreccionClasificacion.class);
        mongo.dropCollection(AjusteCategoria.class);
    }

    private void corregir(int veces, CategoriaColor categoria, Instant cuando) {
        for (int i = 0; i < veces; i++) {
            mongo.insert(new CorreccionClasificacion(UUID.randomUUID().toString(), ROJO_FUERTE, categoria, cuando));
        }
    }

    @Test
    void sinTokenResponde401() throws Exception {
        mockMvc.perform(get(RUTA)).andExpect(status().isUnauthorized());
    }

    @Test
    void conAcuerdoSuficienteElBloqueCambiaYLaAppLoVe() throws Exception {
        corregir(8, CategoriaColor.VINOTINTO, ANTES);
        corregir(2, CategoriaColor.ROSADO, ANTES);

        List<AjusteCategoria> cambios = tarea.ajustar(AHORA);

        assertThat(cambios).singleElement().satisfies(a -> {
            assertThat(a.bloque()).isEqualTo(12);
            assertThat(a.categoria()).isEqualTo("VINOTINTO");
            assertThat(a.categoriaTabla()).isEqualTo("ROJO");
            assertThat(a.correcciones()).isEqualTo(10);
            assertThat(a.acuerdo()).isEqualTo(0.8);
        });
        mockMvc.perform(get(RUTA).with(jwt().jwt(t -> t.subject("sub-colores"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.ajustes[0].bloque").value(12))
                .andExpect(jsonPath("$.ajustes[0].categoria").value("VINOTINTO"));
    }

    @Test
    void sinAcuerdoNoCambiaNada() throws Exception {
        corregir(6, CategoriaColor.VINOTINTO, ANTES);
        corregir(4, CategoriaColor.ROSADO, ANTES);

        assertThat(tarea.ajustar(AHORA)).isEmpty();
        mockMvc.perform(get(RUTA).with(jwt().jwt(t -> t.subject("sub-colores"))))
                .andExpect(jsonPath("$.ajustes").isEmpty());
    }

    @Test
    void lasCorreccionesYaUsadasNoVuelvenAContar() {
        corregir(10, CategoriaColor.VINOTINTO, ANTES);
        assertThat(tarea.ajustar(AHORA)).hasSize(1);

        // Las mismas diez no deciden otra vez; diez nuevas que piden ROSADO si.
        assertThat(tarea.ajustar(AHORA.plusSeconds(60))).isEmpty();
        corregir(10, CategoriaColor.ROSADO, AHORA.plusSeconds(120));
        assertThat(tarea.ajustar(AHORA.plusSeconds(180)))
                .singleElement()
                .satisfies(a -> assertThat(a.categoria()).isEqualTo("ROSADO"));
    }
}
