package com.wearhack;

import static org.hamcrest.Matchers.startsWith;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.RequestBuilder;

/**
 * El 100 % de los accesos sin un token valido se rechaza (issue #21, criterio de calidad 3).
 *
 * <p>Corre sin User Pool configurado, que es el caso de local y de CI: ahi cualquier token
 * se rechaza, firmado o no. Que un token de Cognito bien firmado pase lo prueba
 * {@code ValidacionCognitoTest}; que un usuario no llegue a los datos de otro,
 * {@code UsuariosMongoTest}.
 */
@SpringBootTest
@AutoConfigureMockMvc
class SeguridadTest {

    @Autowired
    private MockMvc mockMvc;

    @ParameterizedTest
    @ValueSource(strings = {"/api/v1/usuarios/me", "/api/v1/usuarios/me/colorimetria",
        "/api/v1/usuarios/me/consentimientos", "/actuator/metrics"})
    void sinTokenSeRechazaCon401(String ruta) throws Exception {
        rechazado(get(ruta));
    }

    @ParameterizedTest
    @ValueSource(strings = {"Bearer no-es-un-jwt",
        "Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJ5byJ9.",
        "Basic dXN1YXJpbzpjbGF2ZQ=="})
    void conUnTokenInvalidoSeRechazaCon401(String autorizacion) throws Exception {
        rechazado(get("/api/v1/usuarios/me").header(HttpHeaders.AUTHORIZATION, autorizacion));
    }

    @Test
    void tampocoSePuedeEscribirNiBorrarSinToken() throws Exception {
        rechazado(put("/api/v1/usuarios/me")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"mayorDeEdad\":true}"));
        rechazado(delete("/api/v1/usuarios/me"));
        rechazado(delete("/api/v1/usuarios/me/consentimientos/colorimetria"));
    }

    private void rechazado(RequestBuilder peticion) throws Exception {
        mockMvc.perform(peticion)
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, startsWith("Bearer")))
                .andExpect(jsonPath("$.estado").value(401));
    }
}
