package com.wearhack;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;
import org.springframework.modulith.docs.Documenter;

/**
 * Genera el diagrama de modulos con {@code Documenter}, que emite PlantUML.
 *
 * <p>Por defecto escribe en {@code target/}, asi que un {@code mvn verify} normal no
 * toca el arbol de trabajo. Para actualizar lo que se versiona en {@code docs/modulith/}:
 *
 * <pre>
 * mvn -B -f services/core/pom.xml test -Dtest=DocumentacionModulithTest \
 *     -Dwearhack.docs.salida=../../docs/modulith
 * </pre>
 *
 * <p>GitHub no renderiza PlantUML, asi que el diagrama de modulos que se lee en el
 * repositorio se mantiene aparte, en Mermaid, en {@code docs/arquitectura.md}. Estos
 * {@code .puml} son la version generada, para regenerar y comparar.
 */
class DocumentacionModulithTest {

    private static final String SALIDA_POR_DEFECTO = "target/spring-modulith-docs";

    @Test
    void generaLosDiagramasDeModulos() throws IOException {
        String carpeta = System.getProperty("wearhack.docs.salida", SALIDA_POR_DEFECTO);
        var opciones = Documenter.Options.defaults().withOutputFolder(carpeta);

        new Documenter(ApplicationModules.of(WearHackApplication.class), opciones)
                .writeModulesAsPlantUml()
                .writeIndividualModulesAsPlantUml();

        Path diagrama = Path.of(carpeta, "components.puml");
        assertThat(diagrama).exists();
        // Documenter dibuja los nombres para mostrar (displayName), no los del paquete.
        assertThat(Files.readString(diagrama))
                .contains("Usuarios", "Closet", "Outfits", "Publicidad", "Plataforma");
    }
}
