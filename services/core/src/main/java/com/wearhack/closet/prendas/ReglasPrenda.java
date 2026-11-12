package com.wearhack.closet.prendas;

import static com.wearhack.closet.prendas.Clima.CALIDO;
import static com.wearhack.closet.prendas.Clima.FRIO;
import static com.wearhack.closet.prendas.Clima.TEMPLADO;
import static com.wearhack.closet.prendas.Formalidad.CASUAL;
import static com.wearhack.closet.prendas.Formalidad.DEPORTIVO;
import static com.wearhack.closet.prendas.Formalidad.FORMAL;
import static com.wearhack.closet.prendas.Formalidad.SMART_CASUAL;

import com.wearhack.plataforma.ReglaDeNegocioException;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;

/**
 * Las reglas de C.18 que no se le pueden pedir al {@code $jsonSchema} de Mongo, y los valores
 * que se deducen del tipo y la textura. Estaticas a proposito: estan definidas, no se calibran.
 */
public final class ReglasPrenda {

    private static final Set<Clima> TODOS = EnumSet.allOf(Clima.class);

    private ReglasPrenda() {}

    /**
     * Completa y valida lo que manda el dispositivo.
     *
     * @param textura {@code null} para usar la de por defecto del tipo
     * @param formalidad {@code null} para usar la de por defecto; si viene, gana (el usuario la edito)
     * @throws ReglaDeNegocioException si la combinacion no tiene sentido
     */
    public static Atributos completar(Tipo tipo, SubtipoCalzado subtipo, Patron patron, Textura textura,
            RangoFormalidad formalidad, ColorPrenda color) {
        if (tipo == null || patron == null || color == null) {
            throw new ReglaDeNegocioException("La prenda necesita tipo, patron y color");
        }
        if (subtipo != null && tipo != Tipo.CALZADO) {
            throw new ReglaDeNegocioException("El subtipo de calzado solo aplica al calzado");
        }
        Textura texturaFinal;
        if (tipo.slot().llevaTextura()) {
            texturaFinal = textura != null ? textura : texturaPorDefecto(tipo);
        } else if (textura != null) {
            throw new ReglaDeNegocioException("El calzado y los accesorios no llevan textura");
        } else {
            texturaFinal = null;
        }
        RangoFormalidad formalidadFinal =
                formalidad != null ? formalidad : formalidadPorDefecto(tipo, texturaFinal, subtipo);
        return new Atributos(tipo, subtipo, patron, texturaFinal, formalidadFinal,
                climaApto(tipo, texturaFinal, subtipo), color);
    }

    /**
     * La de por defecto. En PANTALON, CHAQUETA, FALDA, VESTIDO y CHALECO la pantalla de revision
     * pregunta; esta es la primera opcion, la que va preseleccionada.
     */
    static Textura texturaPorDefecto(Tipo tipo) {
        return switch (tipo) {
            case CAMISETA, CAMISA, ENTERIZO, SHORT, FALDA, VESTIDO -> Textura.LISO_LIGERO;
            case SUETER, CARDIGAN -> Textura.PUNTO;
            case ABRIGO -> Textura.PANO;
            case PANTALON, CHAQUETA -> Textura.DENIM;
            case CHALECO -> Textura.ACOLCHADO;
            default -> null;
        };
    }

    /** {@code null} en los accesorios neutros. */
    static RangoFormalidad formalidadPorDefecto(Tipo tipo, Textura textura, SubtipoCalzado subtipo) {
        return switch (tipo) {
            case CAMISETA, SHORT -> textura == Textura.DEPORTIVO ? rango(DEPORTIVO) : rango(CASUAL);
            case CAMISA -> textura == Textura.DENIM || textura == Textura.LINO
                    ? rango(CASUAL) : rango(SMART_CASUAL, FORMAL);
            case SUETER, CARDIGAN, ENTERIZO -> rango(CASUAL);
            case CHAQUETA, PANTALON -> switch (textura == null ? Textura.OTRA : textura) {
                case PANO -> rango(SMART_CASUAL, FORMAL);
                case DEPORTIVO -> rango(DEPORTIVO);
                default -> rango(CASUAL);
            };
            case ABRIGO -> rango(SMART_CASUAL);
            case CHALECO -> textura == Textura.PANO ? rango(FORMAL) : rango(CASUAL);
            case FALDA -> textura == Textura.SATIN ? rango(SMART_CASUAL) : rango(CASUAL);
            case VESTIDO -> textura == Textura.SATIN ? rango(FORMAL) : rango(CASUAL);
            case CALZADO -> subtipo == SubtipoCalzado.ZAPATO_FORMAL || subtipo == SubtipoCalzado.TACONES
                    ? rango(SMART_CASUAL, FORMAL) : rango(CASUAL);
            case CORBATA -> rango(SMART_CASUAL, FORMAL);
            default -> null;
        };
    }

    /** Primero manda la regla del tipo, si la hay; si no, la de la textura. En orden FRIO, TEMPLADO, CALIDO. */
    static List<Clima> climaApto(Tipo tipo, Textura textura, SubtipoCalzado subtipo) {
        Set<Clima> climas = switch (tipo) {
            case ABRIGO, BUFANDA -> EnumSet.of(FRIO);
            case SHORT -> EnumSet.of(TEMPLADO, CALIDO);
            case CAMISETA, CAMISA -> TODOS;
            case CALZADO -> subtipo == SubtipoCalzado.SANDALIAS ? EnumSet.of(TEMPLADO, CALIDO)
                    : subtipo == SubtipoCalzado.BOTAS ? EnumSet.of(FRIO, TEMPLADO)
                    : TODOS;
            default -> tipo.slot().llevaTextura() ? porTextura(textura) : TODOS;
        };
        return List.copyOf(EnumSet.copyOf(climas));
    }

    private static Set<Clima> porTextura(Textura textura) {
        return switch (textura == null ? Textura.OTRA : textura) {
            case LISO_LIGERO, LINO, SATIN -> EnumSet.of(TEMPLADO, CALIDO);
            case DENIM, PUNTO, PANO, CUERO -> EnumSet.of(FRIO, TEMPLADO);
            case ACOLCHADO -> EnumSet.of(FRIO);
            case DEPORTIVO, OTRA -> TODOS;
        };
    }

    private static RangoFormalidad rango(Formalidad nivel) {
        return RangoFormalidad.de(nivel);
    }

    private static RangoFormalidad rango(Formalidad min, Formalidad max) {
        return new RangoFormalidad(min, max);
    }
}
