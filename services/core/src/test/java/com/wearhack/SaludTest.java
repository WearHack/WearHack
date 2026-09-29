package com.wearhack;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Comprueba lo que este esqueleto promete: que el contexto levanta y que el Core y
 * cada modulo responden.
 *
 * <p>Va con MockMvc y no con un servidor real: no abre puertos, asi que corre igual en
 * cualquier runner y tarda poco. Que responda de verdad por HTTP se comprueba en el
 * compose.
 */
@SpringBootTest
@AutoConfigureMockMvc
class SaludTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void elCoreResponde() throws Exception {
        mockMvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.servicio").value("core"))
                .andExpect(jsonPath("$.estado").value("UP"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"usuarios", "closet", "outfits", "publicidad"})
    void cadaModuloResponde(String modulo) throws Exception {
        mockMvc.perform(get("/api/v1/" + modulo + "/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.servicio").value("core"))
                .andExpect(jsonPath("$.modulo").value(modulo))
                .andExpect(jsonPath("$.estado").value("UP"));
    }

    @Test
    void actuatorResponde() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
