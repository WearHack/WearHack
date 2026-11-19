package com.wearhack.closet.colores;

import static org.assertj.core.api.Assertions.assertThat;

import com.wearhack.closet.colores.AjusteCategoriasColor.Decision;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/** La regla de #58 sin Mongo: 10 correcciones o mas y 70 % de acuerdo. */
class AjusteCategoriasColorTest {

    private static List<String> correcciones(int vinotinto, int rosado) {
        List<String> c = new ArrayList<>(Collections.nCopies(vinotinto, "VINOTINTO"));
        c.addAll(Collections.nCopies(rosado, "ROSADO"));
        return c;
    }

    @Test
    void conMenosDeDiezNoCambia() {
        assertThat(AjusteCategoriasColor.decidir(correcciones(9, 0), "ROJO")).isEmpty();
    }

    @Test
    void conDiezYSetentaPorCientoCambia() {
        Optional<Decision> d = AjusteCategoriasColor.decidir(correcciones(7, 3), "ROJO");
        assertThat(d).contains(new Decision("VINOTINTO", 10, 0.7));
    }

    @Test
    void pordebajoDelSetentaPorCientoNoCambia() {
        assertThat(AjusteCategoriasColor.decidir(correcciones(6, 4), "ROJO")).isEmpty();
        assertThat(AjusteCategoriasColor.decidir(correcciones(13, 7), "ROJO")).isEmpty();
    }

    @Test
    void siLaMayoriaPideLaCategoriaVigenteNoCambia() {
        assertThat(AjusteCategoriasColor.decidir(correcciones(10, 0), "VINOTINTO")).isEmpty();
    }
}
