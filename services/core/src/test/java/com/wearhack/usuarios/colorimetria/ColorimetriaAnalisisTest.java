package com.wearhack.usuarios.colorimetria;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import com.wearhack.usuarios.colorimetria.ClienteColorimetria;
import com.wearhack.usuarios.colorimetria.Consentimiento;
import com.wearhack.usuarios.colorimetria.ConsentimientoRepository;
import com.wearhack.usuarios.colorimetria.Lab;
import com.wearhack.usuarios.colorimetria.PerfilColorimetriaRepository;
import com.wearhack.usuarios.colorimetria.ResultadoColorimetria;
import com.wearhack.MongoDePrueba;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import com.wearhack.usuarios.colorimetria.ClienteColorimetria;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class ColorimetriaAnalisisTest {

    private static final String SUB = "sub-colorimetria-test";

    private static final byte[] PNG = {
        (byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3
    };

    private static final Instant AHORA =
            Instant.parse("2026-10-15T12:00:00Z");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ConsentimientoRepository consentimientos;

    @Autowired
    private PerfilColorimetriaRepository perfiles;

    @MockitoBean
    private ClienteColorimetria ia;

    @BeforeEach
    void preparar() {
        perfiles.deleteAll();
        consentimientos.deleteAll();
    }

    @Test
    void sinTokenResponde401() throws Exception {
        mockMvc.perform(post("/api/v1/usuarios/me/colorimetria")
                        .contentType(MediaType.IMAGE_PNG)
                        .content(PNG))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void contentTypeIncorrectoResponde415() throws Exception {
        mockMvc.perform(post("/api/v1/usuarios/me/colorimetria")
                        .with(usuarioAutenticado())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isUnsupportedMediaType());
    }

    @Test
    void pngValidoConConsentimientoResponde200YGuardaPerfil() throws Exception {
        otorgarConsentimiento();

        when(ia.analizar(any(byte[].class)))
                .thenReturn(new ResultadoColorimetria(
                        "otono",
                        0.82,
                        List.of("piel", "iris"),
                        new Lab(62.1, 14.3, 18.9),
                        null,
                        new Lab(35.5, 2.0, 12.4)));

        mockMvc.perform(post("/api/v1/usuarios/me/colorimetria")
                        .with(usuarioAutenticado())
                        .contentType(MediaType.IMAGE_PNG)
                        .content(PNG))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.temporada").value("otono"))
                .andExpect(jsonPath("$.confianza").value(0.82))
                .andExpect(jsonPath("$.ejes[0]").value("piel"))
                .andExpect(jsonPath("$.ejes[1]").value("iris"));

        var perfil = perfiles.findById(SUB);
        org.assertj.core.api.Assertions.assertThat(perfil).isPresent();
        org.assertj.core.api.Assertions.assertThat(perfil.get().temporada())
                .isEqualTo("otono");
    }

    @Test
    void sinConsentimientoResponde422() throws Exception {
        mockMvc.perform(post("/api/v1/usuarios/me/colorimetria")
                        .with(usuarioAutenticado())
                        .contentType(MediaType.IMAGE_PNG)
                        .content(PNG))
                .andExpect(status().isUnprocessableContent());
    }

    @Test
    void cuerpoMayorAlLimiteResponde413() throws Exception {
        byte[] grande = new byte[5 * 1024 * 1024 + 1];

        mockMvc.perform(post("/api/v1/usuarios/me/colorimetria")
                        .with(usuarioAutenticado())
                        .contentType(MediaType.IMAGE_PNG)
                        .content(grande))
                .andExpect(status().is(413));
    }

    @Test
    void iaNoDisponibleResponde503YSinGuardarPerfil() throws Exception {
        otorgarConsentimiento();

        when(ia.analizar(any(byte[].class)))
                .thenThrow(new ServicioIaNoDisponibleException("IA no disponible", null));

        mockMvc.perform(post("/api/v1/usuarios/me/colorimetria")
                        .with(usuarioAutenticado())
                        .contentType(MediaType.IMAGE_PNG)
                        .content(PNG))
                .andExpect(status().isServiceUnavailable());

        org.assertj.core.api.Assertions.assertThat(perfiles.findById(SUB))
                .isEmpty();
    }

    private RequestPostProcessor usuarioAutenticado() {
        return jwt().jwt(token -> token.subject(SUB));
    }

    private void otorgarConsentimiento() {
        consentimientos.save(new Consentimiento(
                "consentimiento-test",
                SUB,
                "colorimetria",
                "v1",
                Consentimiento.OTORGADO,
                AHORA,
                null));
    }
}
