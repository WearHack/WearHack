package com.wearhack.outfits;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Comprueba lo unico que este esqueleto promete: que el contexto levanta y que
 * los dos health checks responden.
 *
 * <p>Va con MockMvc y no con un servidor real a proposito. No abre puertos, asi
 * que corre igual en cualquier runner de CI y tarda menos de un segundo. Que el
 * servicio responda de verdad por HTTP se comprueba mas arriba, en el compose.
 */
@SpringBootTest
@AutoConfigureMockMvc
class OutfitsApplicationTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void elHealthDeNegocioResponde() throws Exception {
        mockMvc.perform(get("/api/v1/outfits/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.servicio").value("outfits"))
                .andExpect(jsonPath("$.estado").value("UP"));
    }

    @Test
    void elHealthDeActuatorResponde() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
