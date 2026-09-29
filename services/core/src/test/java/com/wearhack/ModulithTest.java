package com.wearhack;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.ApplicationModule;
import org.springframework.modulith.core.ApplicationModules;

/**
 * Las fronteras entre modulos se verifican aqui, no se dejan a la convencion de
 * nombres de paquetes.
 */
class ModulithTest {

    private static final ApplicationModules MODULOS =
            ApplicationModules.of(WearHackApplication.class);

    /**
     * Falla si un modulo depende de otro que no tiene declarado, o si hay un ciclo.
     * Es la prueba de que las fronteras existen de verdad.
     */
    @Test
    void lasFronterasSeRespetan() {
        MODULOS.verify();
    }

    @Test
    void estanLosModulosEsperados() {
        Set<String> nombres = MODULOS.stream()
                .map(modulo -> modulo.getIdentifier().toString())
                .collect(Collectors.toSet());

        assertThat(nombres)
                .containsExactlyInAnyOrder(
                        "usuarios", "closet", "outfits", "publicidad", "plataforma");
    }

    /**
     * {@code verify()} solo hace cumplir lo que esta declarado. Si alguien borra el
     * {@code allowedDependencies} de un modulo, pasa a no tener restricciones y
     * {@code verify()} sigue en verde. Este test vigila que las declaraciones no se
     * pierdan en silencio.
     *
     * <p>Un array vacio prohibe toda dependencia; dejar el atributo por defecto no
     * restringe nada. Por eso importa distinguir entre "vacio" y "ausente".
     */
    @Test
    void lasDependenciasDeclaradasSonLasQueSeDecidieron() throws Exception {
        Map<String, Set<String>> esperadas = Map.of(
                "usuarios", Set.of(),
                "publicidad", Set.of(),
                "plataforma", Set.of(),
                "closet", Set.of("usuarios"),
                "outfits", Set.of("usuarios", "closet", "publicidad"));

        for (var esperada : esperadas.entrySet()) {
            String paquete = "com.wearhack." + esperada.getKey();
            ApplicationModule declaracion = Class.forName(paquete + ".package-info")
                    .getPackage()
                    .getAnnotation(ApplicationModule.class);

            assertThat(declaracion)
                    .as("%s debe llevar @ApplicationModule en su package-info", paquete)
                    .isNotNull();
            assertThat(Set.of(declaracion.allowedDependencies()))
                    .as("dependencias permitidas de %s", esperada.getKey())
                    .isEqualTo(esperada.getValue());
        }
    }
}
