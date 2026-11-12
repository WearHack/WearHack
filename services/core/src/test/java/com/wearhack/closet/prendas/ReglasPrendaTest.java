package com.wearhack.closet.prendas;

import static com.wearhack.closet.prendas.Clima.CALIDO;
import static com.wearhack.closet.prendas.Clima.FRIO;
import static com.wearhack.closet.prendas.Clima.TEMPLADO;
import static com.wearhack.closet.prendas.Formalidad.CASUAL;
import static com.wearhack.closet.prendas.Formalidad.DEPORTIVO;
import static com.wearhack.closet.prendas.Formalidad.FORMAL;
import static com.wearhack.closet.prendas.Formalidad.SMART_CASUAL;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.wearhack.plataforma.ReglaDeNegocioException;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** Las tablas de respuestas C.18: slot, textura, formalidad y clima por defecto. */
class ReglasPrendaTest {

    private static final ColorPrenda AZUL = new ColorPrenda(List.of(40.0, 5.0, -40.0), CategoriaColor.AZUL);

    private static Atributos completar(Tipo tipo, Textura textura) {
        return ReglasPrenda.completar(tipo, null, Patron.LISO, textura, null, AZUL);
    }

    private static Atributos calzado(SubtipoCalzado subtipo) {
        return ReglasPrenda.completar(Tipo.CALZADO, subtipo, Patron.LISO, null, null, AZUL);
    }

    @ParameterizedTest
    @CsvSource({
        "CAMISA, TORSO_SUPERIOR", "SUETER, TORSO_SUPERIOR", "CARDIGAN, EXTERIOR", "CHALECO, EXTERIOR",
        "FALDA, TORSO_INFERIOR", "ENTERIZO, CUERPO_COMPLETO", "CALZADO, CALZADO",
        "GAFAS, ACCESORIO_OJOS", "ACCESORIO_CABELLO, ACCESORIO_CABEZA", "BUFANDA, ACCESORIO_CUELLO",
        "JOYERIA, ACCESORIO_JOYERIA",
    })
    void cadaTipoTieneSuSlot(Tipo tipo, SlotOutfit slot) {
        assertThat(tipo.slot()).isEqualTo(slot);
    }

    @ParameterizedTest
    @CsvSource({
        "CAMISETA, LISO_LIGERO", "CAMISA, LISO_LIGERO", "ENTERIZO, LISO_LIGERO", "SHORT, LISO_LIGERO",
        "SUETER, PUNTO", "CARDIGAN, PUNTO", "ABRIGO, PANO",
        // Estos se preguntan en la revision: va la primera opcion, la preseleccionada.
        "PANTALON, DENIM", "CHAQUETA, DENIM", "FALDA, LISO_LIGERO", "VESTIDO, LISO_LIGERO", "CHALECO, ACOLCHADO",
    })
    void sinTexturaVaLaDePorDefecto(Tipo tipo, Textura esperada) {
        assertThat(completar(tipo, null).textura()).isEqualTo(esperada);
    }

    @Test
    void laTexturaQueMandaElUsuarioGana() {
        assertThat(completar(Tipo.PANTALON, Textura.PANO).textura()).isEqualTo(Textura.PANO);
    }

    @Test
    void calzadoYAccesoriosNoLlevanTextura() {
        assertThat(calzado(null).textura()).isNull();
        assertThat(completar(Tipo.RELOJ, null).textura()).isNull();
        assertThatThrownBy(() -> completar(Tipo.BOLSO, Textura.CUERO))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    @Test
    void elSubtipoSoloAplicaAlCalzado() {
        assertThatThrownBy(() -> ReglasPrenda.completar(
                Tipo.PANTALON, SubtipoCalzado.BOTAS, Patron.LISO, null, null, AZUL))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    @ParameterizedTest
    @CsvSource({
        "CAMISETA, LISO_LIGERO, CASUAL, CASUAL",
        "CAMISETA, DEPORTIVO, DEPORTIVO, DEPORTIVO",
        "CAMISA, LISO_LIGERO, SMART_CASUAL, FORMAL",
        "CAMISA, DENIM, CASUAL, CASUAL",
        "CAMISA, LINO, CASUAL, CASUAL",
        "SUETER, PUNTO, CASUAL, CASUAL",
        "CHAQUETA, DENIM, CASUAL, CASUAL",
        "CHAQUETA, PANO, SMART_CASUAL, FORMAL",
        "CHAQUETA, DEPORTIVO, DEPORTIVO, DEPORTIVO",
        "ABRIGO, PANO, SMART_CASUAL, SMART_CASUAL",
        "CHALECO, PANO, FORMAL, FORMAL",
        "CHALECO, ACOLCHADO, CASUAL, CASUAL",
        "PANTALON, PANO, SMART_CASUAL, FORMAL",
        "PANTALON, DEPORTIVO, DEPORTIVO, DEPORTIVO",
        "SHORT, DEPORTIVO, DEPORTIVO, DEPORTIVO",
        "FALDA, SATIN, SMART_CASUAL, SMART_CASUAL",
        "VESTIDO, SATIN, FORMAL, FORMAL",
        "VESTIDO, LISO_LIGERO, CASUAL, CASUAL",
    })
    void formalidadPorDefecto(Tipo tipo, Textura textura, Formalidad min, Formalidad max) {
        assertThat(completar(tipo, textura).formalidad()).isEqualTo(new RangoFormalidad(min, max));
    }

    @Test
    void formalidadDelCalzadoSaleDelSubtipo() {
        assertThat(calzado(null).formalidad()).isEqualTo(RangoFormalidad.de(CASUAL));
        assertThat(calzado(SubtipoCalzado.TENIS).formalidad()).isEqualTo(RangoFormalidad.de(CASUAL));
        assertThat(calzado(SubtipoCalzado.ZAPATO_FORMAL).formalidad())
                .isEqualTo(new RangoFormalidad(SMART_CASUAL, FORMAL));
        assertThat(calzado(SubtipoCalzado.TACONES).formalidad())
                .isEqualTo(new RangoFormalidad(SMART_CASUAL, FORMAL));
    }

    @Test
    void losAccesoriosSonNeutrosSalvoLaCorbata() {
        assertThat(completar(Tipo.RELOJ, null).formalidad()).isNull();
        assertThat(completar(Tipo.JOYERIA, null).formalidad()).isNull();
        assertThat(completar(Tipo.CORBATA, null).formalidad())
                .isEqualTo(new RangoFormalidad(SMART_CASUAL, FORMAL));
    }

    @Test
    void laFormalidadQueMandaElUsuarioGana() {
        var editada = new RangoFormalidad(CASUAL, SMART_CASUAL);
        var atributos = ReglasPrenda.completar(Tipo.CAMISA, null, Patron.LISO, null, editada, AZUL);
        assertThat(atributos.formalidad()).isEqualTo(editada);
    }

    @Test
    void unRangoAlRevesSeRechaza() {
        assertThatThrownBy(() -> new RangoFormalidad(FORMAL, DEPORTIVO))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    @ParameterizedTest
    @CsvSource({
        "LISO_LIGERO, TEMPLADO CALIDO", "LINO, TEMPLADO CALIDO", "SATIN, TEMPLADO CALIDO",
        "DENIM, FRIO TEMPLADO", "PUNTO, FRIO TEMPLADO", "PANO, FRIO TEMPLADO", "CUERO, FRIO TEMPLADO",
        "ACOLCHADO, FRIO", "DEPORTIVO, FRIO TEMPLADO CALIDO", "OTRA, FRIO TEMPLADO CALIDO",
    })
    void sinReglaDeTipoElClimaSaleDeLaTextura(Textura textura, String climas) {
        // PANTALON no tiene regla propia de clima.
        assertThat(completar(Tipo.PANTALON, textura).climaApto()).isEqualTo(climas(climas));
    }

    @Test
    void laReglaDelTipoMandaSobreLaTextura() {
        assertThat(completar(Tipo.ABRIGO, Textura.LINO).climaApto()).containsExactly(FRIO);
        assertThat(completar(Tipo.SHORT, Textura.DENIM).climaApto()).containsExactly(TEMPLADO, CALIDO);
        // Por eso la camisa es apta para frio: la capa la exige la regla del outfit.
        assertThat(completar(Tipo.CAMISA, Textura.LINO).climaApto()).containsExactly(FRIO, TEMPLADO, CALIDO);
        assertThat(completar(Tipo.CAMISETA, null).climaApto()).containsExactly(FRIO, TEMPLADO, CALIDO);
    }

    @Test
    void elClimaDelCalzadoYLosAccesoriosSaleDelTipo() {
        assertThat(calzado(SubtipoCalzado.SANDALIAS).climaApto()).containsExactly(TEMPLADO, CALIDO);
        assertThat(calzado(SubtipoCalzado.BOTAS).climaApto()).containsExactly(FRIO, TEMPLADO);
        assertThat(calzado(null).climaApto()).containsExactly(FRIO, TEMPLADO, CALIDO);
        assertThat(completar(Tipo.BUFANDA, null).climaApto()).containsExactly(FRIO);
        assertThat(completar(Tipo.GAFAS, null).climaApto()).containsExactly(FRIO, TEMPLADO, CALIDO);
    }

    @Test
    void elColorNecesitaTresValoresYCategoria() {
        assertThatThrownBy(() -> new ColorPrenda(List.of(1.0, 2.0), CategoriaColor.ROJO))
                .isInstanceOf(ReglaDeNegocioException.class);
        assertThatThrownBy(() -> new ColorPrenda(List.of(120.0, 0.0, 0.0), CategoriaColor.BLANCO))
                .isInstanceOf(ReglaDeNegocioException.class);
        assertThatThrownBy(() -> new ColorPrenda(List.of(50.0, Double.NaN, 0.0), CategoriaColor.GRIS))
                .isInstanceOf(ReglaDeNegocioException.class);
        assertThatThrownBy(() -> new ColorPrenda(List.of(50.0, 0.0, 0.0), null))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    private static List<Clima> climas(String nombres) {
        return java.util.Arrays.stream(nombres.split(" ")).map(Clima::valueOf).toList();
    }
}
