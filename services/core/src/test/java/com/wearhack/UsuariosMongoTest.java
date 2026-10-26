package com.wearhack;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.hasSize;
import static org.mockito.Mockito.verify;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.plataforma.ProveedorIdentidad;
import com.wearhack.usuarios.colorimetria.CorreccionColorimetria;
import com.wearhack.usuarios.colorimetria.Lab;
import com.wearhack.usuarios.colorimetria.PerfilColorimetria;
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
import org.springframework.http.MediaType;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Los endpoints del modulo usuarios de punta a punta, contra un Mongo real.
 *
 * <p>Los tokens los fabrica {@code jwt()}: la validacion contra Cognito tiene sus propias
 * pruebas. Aqui interesa que, una vez autenticado, cada usuario solo alcance lo suyo.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class UsuariosMongoTest {

    private static final String ANA = "sub-ana";
    private static final String BETO = "sub-beto";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MongoTemplate mongo;

    @MockitoBean
    private ProveedorIdentidad proveedorIdentidad;

    @BeforeEach
    void limpiar() {
        mongo.getDb().drop();
    }

    @Test
    void registroConDeclaracionDeMayoriaDeEdad() throws Exception {
        perform(get("/api/v1/usuarios/me"), ANA).andExpect(status().isNotFound());

        registrar(ANA, "{\"nombre\":\"Ana\"}").andExpect(status().isUnprocessableContent());
        registrar(ANA, "{\"nombre\":\"Ana\",\"mayorDeEdad\":false}")
                .andExpect(status().isUnprocessableContent());

        registrar(ANA, "{\"nombre\":\"Ana\",\"mayorDeEdad\":true}")
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(ANA))
                .andExpect(jsonPath("$.mayorDeEdad").value(true))
                .andExpect(jsonPath("$.mayoriaEdadDeclaradaEn").isNotEmpty());

        registrar(ANA, "{\"nombre\":\"Ana Maria\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Ana Maria"));

        perform(get("/api/v1/usuarios/me"), ANA)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Ana Maria"))
                .andExpect(jsonPath("$.mayorDeEdad").value(true));
    }

    @Test
    void unNombreDemasiadoLargoSeRechaza() throws Exception {
        registrar(ANA, "{\"nombre\":\"" + "a".repeat(81) + "\",\"mayorDeEdad\":true}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void ningunUsuarioAlcanzaLosDatosDeOtro() throws Exception {
        anaConPerfilDeColor();

        perform(get("/api/v1/usuarios/me"), BETO).andExpect(status().isNotFound());
        perform(get("/api/v1/usuarios/me/colorimetria"), BETO).andExpect(status().isNotFound());
        perform(get("/api/v1/usuarios/me/consentimientos"), BETO)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(0)));
        perform(delete("/api/v1/usuarios/me/consentimientos/colorimetria"), BETO)
                .andExpect(status().isNotFound());
        perform(delete("/api/v1/usuarios/me/colorimetria"), BETO).andExpect(status().isNoContent());
        perform(delete("/api/v1/usuarios/me"), BETO).andExpect(status().isNoContent());

        // Nada de lo que hizo Beto toco a Ana.
        perform(get("/api/v1/usuarios/me"), ANA).andExpect(status().isOk());
        perform(get("/api/v1/usuarios/me/colorimetria"), ANA)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.temporada").value("otono_profundo"));
        perform(get("/api/v1/usuarios/me/consentimientos"), ANA)
                .andExpect(jsonPath("$[0].estado").value("otorgado"));
    }

    @Test
    void otorgarYRevocarElConsentimiento() throws Exception {
        registrar(ANA, "{\"mayorDeEdad\":true}").andExpect(status().isCreated());

        otorgar(ANA, "2026-10-01").andExpect(status().isCreated())
                .andExpect(jsonPath("$.estado").value("otorgado"));
        otorgar(ANA, "2026-10-01").andExpect(status().isOk());
        otorgar(ANA, "2026-11-01").andExpect(status().isCreated());

        perform(get("/api/v1/usuarios/me/consentimientos"), ANA)
                .andExpect(jsonPath("$", hasSize(2)))
                .andExpect(jsonPath("$[0].versionTexto").value("2026-11-01"))
                .andExpect(jsonPath("$[1].estado").value("sustituido"));

        guardarPerfilDeColor(ANA);
        guardarCorreccion(ANA);
        guardarCorreccion(null);

        perform(delete("/api/v1/usuarios/me/consentimientos/colorimetria"), ANA)
                .andExpect(status().isNoContent());

        perform(get("/api/v1/usuarios/me/consentimientos"), ANA)
                .andExpect(jsonPath("$[0].estado").value("revocado"))
                .andExpect(jsonPath("$[0].revocadoEn").isNotEmpty());
        perform(get("/api/v1/usuarios/me/colorimetria"), ANA).andExpect(status().isNotFound());
        // La desvinculada ya no es de nadie: es un dato agregado y se queda.
        assertThat(mongo.findAll(CorreccionColorimetria.class))
                .singleElement()
                .satisfies(correccion -> assertThat(correccion.usuarioId()).isNull());

        perform(delete("/api/v1/usuarios/me/consentimientos/colorimetria"), ANA)
                .andExpect(status().isNotFound());
    }

    @Test
    void sinRegistroNoSeOtorgaConsentimiento() throws Exception {
        otorgar(ANA, "2026-10-01").andExpect(status().isNotFound());
    }

    @Test
    void unaFinalidadDesconocidaSeRechaza() throws Exception {
        registrar(ANA, "{\"mayorDeEdad\":true}");
        perform(post("/api/v1/usuarios/me/consentimientos")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"finalidad\":\"publicidad\",\"versionTexto\":\"v1\"}"), ANA)
                .andExpect(status().isBadRequest());
        perform(delete("/api/v1/usuarios/me/consentimientos/publicidad"), ANA)
                .andExpect(status().isNotFound());
    }

    @Test
    void borrarElPerfilDeColorDejaElConsentimiento() throws Exception {
        anaConPerfilDeColor();

        perform(delete("/api/v1/usuarios/me/colorimetria"), ANA).andExpect(status().isNoContent());

        perform(get("/api/v1/usuarios/me/colorimetria"), ANA).andExpect(status().isNotFound());
        perform(get("/api/v1/usuarios/me/consentimientos"), ANA)
                .andExpect(jsonPath("$[0].estado").value("otorgado"));
    }

    @Test
    void eliminarLaCuentaBorraTodoYLaCuentaDeCognito() throws Exception {
        anaConPerfilDeColor();
        guardarCorreccion(ANA);
        registrar(BETO, "{\"mayorDeEdad\":true}");

        perform(delete("/api/v1/usuarios/me"), ANA, "Google_1234").andExpect(status().isNoContent());

        perform(get("/api/v1/usuarios/me"), ANA).andExpect(status().isNotFound());
        assertThat(mongo.findAll(PerfilColorimetria.class)).isEmpty();
        assertThat(mongo.findAll(CorreccionColorimetria.class)).isEmpty();
        assertThat(mongo.getCollection("consentimientos").countDocuments()).isZero();
        verify(proveedorIdentidad).eliminarCuenta("Google_1234");

        perform(get("/api/v1/usuarios/me"), BETO).andExpect(status().isOk());
    }

    private void anaConPerfilDeColor() throws Exception {
        registrar(ANA, "{\"nombre\":\"Ana\",\"mayorDeEdad\":true}").andExpect(status().isCreated());
        otorgar(ANA, "2026-10-01").andExpect(status().isCreated());
        guardarPerfilDeColor(ANA);
    }

    /** El perfil lo escribe el flujo de colorimetria, que no es de estos issues. */
    private void guardarPerfilDeColor(String usuarioId) {
        mongo.save(new PerfilColorimetria(usuarioId,
                new Lab(62.1, 14.3, 18.9), new Lab(25.0, 4.1, 8.2), new Lab(35.5, 2.0, 12.4),
                List.of("subtono", "valor", "croma"), "otono_profundo", 0.82, Instant.now()));
    }

    private void guardarCorreccion(String usuarioId) {
        mongo.save(new CorreccionColorimetria(UUID.randomUUID().toString(), usuarioId, new Lab(60, 12, 17),
                "otono_suave", usuarioId == null ? null : Instant.now(), usuarioId == null ? "2026-09" : null));
    }

    private ResultActions registrar(String sub, String cuerpo) throws Exception {
        return perform(put("/api/v1/usuarios/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content(cuerpo), sub);
    }

    private ResultActions otorgar(String sub, String version) throws Exception {
        return perform(post("/api/v1/usuarios/me/consentimientos")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"finalidad\":\"colorimetria\",\"versionTexto\":\"" + version + "\"}"), sub);
    }

    private ResultActions perform(
            org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder peticion, String sub)
            throws Exception {
        return perform(peticion, sub, sub);
    }

    private ResultActions perform(
            org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder peticion,
            String sub,
            String nombreUsuario)
            throws Exception {
        JwtRequestPostProcessor token = jwt().jwt(j -> j
                .subject(sub)
                .claim("username", nombreUsuario)
                .claim("token_use", "access"));
        return mockMvc.perform(peticion.with(token));
    }
}
