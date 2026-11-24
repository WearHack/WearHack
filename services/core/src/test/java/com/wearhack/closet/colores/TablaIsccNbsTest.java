package com.wearhack.closet.colores;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.wearhack.closet.prendas.CategoriaColor;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.core.io.ClassPathResource;

/** La tabla del Core: completa, con las categorias del enum y la misma de la app. */
class TablaIsccNbsTest {

    private final TablaIsccNbs tabla = new TablaIsccNbs();

    @Test
    void tieneLos267BloquesEnOrden() {
        assertThat(tabla.bloques()).extracting(TablaIsccNbs.Bloque::numero)
                .containsExactlyElementsOf(IntStream.rangeClosed(1, 267).boxed().toList());
    }

    @Test
    void lasCategoriasSonLasDeCategoriaColor() {
        var delEnum = Arrays.stream(CategoriaColor.values()).map(Enum::name).collect(Collectors.toSet());
        assertThat(tabla.categorias()).isEqualTo(delEnum);
        assertThat(tabla.bloques()).extracting(TablaIsccNbs.Bloque::categoria)
                .allMatch(delEnum::contains);
    }

    @Test
    void unCentroideCaeEnSuPropioBloque() {
        for (TablaIsccNbs.Bloque b : tabla.bloques()) {
            assertThat(tabla.masCercano(b.lab()[0], b.lab()[1], b.lab()[2]).numero())
                    .isEqualTo(b.numero());
        }
    }

    /**
     * La app y el Core tienen que asignar el mismo bloque. Las dos copias las escribe
     * {@code tools/iscc-nbs/generar_tabla.py}. Se salta fuera del repo (en la imagen de Docker solo
     * esta {@code services/core}).
     */
    @Test
    void esLaMismaTablaQueLaDeLaApp() throws IOException {
        Path app = Path.of("../../client/assets/color/iscc_nbs.json");
        assumeTrue(Files.exists(app), "sin el cliente al lado");
        String core = new ClassPathResource(TablaIsccNbs.RECURSO).getContentAsString(
                java.nio.charset.StandardCharsets.UTF_8);
        assertThat(core).isEqualTo(Files.readString(app));
    }

    /** Pares de la tabla de Sharma, Wu y Dalal (2005), con su ΔE00 publicado. */
    @ParameterizedTest
    @CsvSource({
        "50, 2.6772, -79.7751, 50, 0, -82.7485, 2.0425",
        "50, -1.3802, -84.2814, 50, 0, -82.7485, 1.0000",
        "50, 0, 0, 50, -1, 2, 2.3669",
        "50, 2.49, -0.001, 50, -2.49, 0.0009, 7.1792",
        "50, 2.5, 0, 73, 25, -18, 27.1492",
        "60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644",
        "22.7233, 20.0904, -46.694, 23.0331, 14.973, -42.5619, 2.0373",
        "90.9257, -0.5406, -0.9208, 88.6381, -0.8985, -0.7239, 1.5381",
    })
    void deltaE00(double l1, double a1, double b1, double l2, double a2, double b2, double esperado) {
        assertThat(TablaIsccNbs.deltaE00(l1, a1, b1, l2, a2, b2)).isCloseTo(esperado, within(1e-4));
        assertThat(TablaIsccNbs.deltaE00(l2, a2, b2, l1, a1, b1)).isCloseTo(esperado, within(1e-4));
    }
}
