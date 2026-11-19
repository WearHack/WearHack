package com.wearhack.closet.colores;

import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * La tabla ISCC-NBS de categorias de color de prenda (#58): 267 bloques con su centroide en Lab
 * D65 y su categoria.
 *
 * <p>Es la misma que usa la app ({@code client/assets/color/iscc_nbs.json}); las dos copias las
 * escribe {@code tools/iscc-nbs/generar_tabla.py} y una prueba falla si se separan. El Core la
 * necesita para saber a que bloque pertenece cada correccion de color.
 */
@Component
public class TablaIsccNbs {

    static final String RECURSO = "colores/iscc_nbs.json";

    /** Un bloque ISCC-NBS. {@code lab} es {L, a, b}. */
    public record Bloque(int numero, String nombre, double[] lab, String categoria) {}

    private final List<Bloque> bloques;
    private final Set<String> categorias;

    public TablaIsccNbs() {
        this(new ClassPathResource(RECURSO));
    }

    TablaIsccNbs(ClassPathResource recurso) {
        try (InputStream entrada = recurso.getInputStream()) {
            JsonNode raiz = JsonMapper.builder().build().readTree(entrada);
            List<Bloque> leidos = new ArrayList<>();
            for (JsonNode b : raiz.get("bloques")) {
                JsonNode lab = b.get("lab");
                leidos.add(new Bloque(
                        b.get("numero").asInt(),
                        b.get("nombre").asString(),
                        new double[] {lab.get(0).asDouble(), lab.get(1).asDouble(), lab.get(2).asDouble()},
                        b.get("categoria").asString()));
            }
            Set<String> nombres = new LinkedHashSet<>();
            raiz.get("categorias").forEach(c -> nombres.add(c.asString()));
            this.bloques = List.copyOf(leidos);
            this.categorias = Set.copyOf(nombres);
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo leer " + RECURSO, e);
        }
        if (bloques.isEmpty()) {
            throw new IllegalStateException(RECURSO + " no tiene bloques");
        }
    }

    public List<Bloque> bloques() {
        return bloques;
    }

    /** Las 20 categorias, con los nombres de {@code CategoriaColor}. */
    public Set<String> categorias() {
        return categorias;
    }

    /** El bloque con numero {@code numero} (1 a 267). */
    public Bloque bloque(int numero) {
        return bloques.get(numero - 1);
    }

    /** El bloque con menor ΔE00 al color. */
    public Bloque masCercano(double l, double a, double b) {
        Bloque mejor = bloques.getFirst();
        double distancia = Double.POSITIVE_INFINITY;
        for (Bloque bloque : bloques) {
            double d = deltaE00(l, a, b, bloque.lab()[0], bloque.lab()[1], bloque.lab()[2]);
            if (d < distancia) {
                distancia = d;
                mejor = bloque;
            }
        }
        return mejor;
    }

    /**
     * Diferencia de color CIEDE2000 (Sharma, Wu y Dalal, 2005), con kL = kC = kH = 1. Es la misma
     * formula que {@code deltaE00} de la app.
     */
    static double deltaE00(double l1, double a1, double b1, double l2, double a2, double b2) {
        double c1 = Math.hypot(a1, b1);
        double c2 = Math.hypot(a2, b2);
        double cMedio7 = Math.pow((c1 + c2) / 2, 7);
        double g = 0.5 * (1 - Math.sqrt(cMedio7 / (cMedio7 + Math.pow(25, 7))));
        double ap1 = (1 + g) * a1;
        double ap2 = (1 + g) * a2;
        double cp1 = Math.hypot(ap1, b1);
        double cp2 = Math.hypot(ap2, b2);
        double h1 = matiz(b1, ap1);
        double h2 = matiz(b2, ap2);

        double dL = l2 - l1;
        double dC = cp2 - cp1;
        double dh = 0;
        if (cp1 * cp2 != 0) {
            dh = h2 - h1;
            if (dh > 180) {
                dh -= 360;
            } else if (dh < -180) {
                dh += 360;
            }
        }
        double dH = 2 * Math.sqrt(cp1 * cp2) * Math.sin(Math.toRadians(dh / 2));

        double lMedio = (l1 + l2) / 2;
        double cpMedio = (cp1 + cp2) / 2;
        double hMedio = h1 + h2;
        if (cp1 * cp2 != 0) {
            if (Math.abs(h1 - h2) <= 180) {
                hMedio = (h1 + h2) / 2;
            } else if (h1 + h2 < 360) {
                hMedio = (h1 + h2 + 360) / 2;
            } else {
                hMedio = (h1 + h2 - 360) / 2;
            }
        }
        double t = 1
                - 0.17 * Math.cos(Math.toRadians(hMedio - 30))
                + 0.24 * Math.cos(Math.toRadians(2 * hMedio))
                + 0.32 * Math.cos(Math.toRadians(3 * hMedio + 6))
                - 0.20 * Math.cos(Math.toRadians(4 * hMedio - 63));
        double dTheta = 30 * Math.exp(-Math.pow((hMedio - 275) / 25, 2));
        double cpMedio7 = Math.pow(cpMedio, 7);
        double rC = 2 * Math.sqrt(cpMedio7 / (cpMedio7 + Math.pow(25, 7)));
        double lm50 = (lMedio - 50) * (lMedio - 50);
        double sL = 1 + 0.015 * lm50 / Math.sqrt(20 + lm50);
        double sC = 1 + 0.045 * cpMedio;
        double sH = 1 + 0.015 * cpMedio * t;
        double rT = -Math.sin(Math.toRadians(2 * dTheta)) * rC;

        double l = dL / sL;
        double c = dC / sC;
        double h = dH / sH;
        return Math.sqrt(l * l + c * c + h * h + rT * c * h);
    }

    private static double matiz(double b, double a) {
        if (a == 0 && b == 0) {
            return 0;
        }
        double h = Math.toDegrees(Math.atan2(b, a));
        return h < 0 ? h + 360 : h;
    }
}
