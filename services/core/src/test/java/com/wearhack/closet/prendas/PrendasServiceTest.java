package com.wearhack.closet.prendas;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.plataforma.ReglaDeNegocioException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/** Guardar, corregir y borrar prendas (issue #25), sin Mongo ni S3. */
class PrendasServiceTest {

    private static final String SUB = "sub-ana";
    private static final String ID = "0b6f3a6e-7d55-4c1e-9b8f-3f2a1c9d4e10";
    private static final Instant AHORA = Instant.parse("2026-11-11T12:00:00Z");
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3};
    private static final ColorPrenda AZUL = new ColorPrenda(List.of(40.0, 5.0, -40.0), CategoriaColor.AZUL);
    private static final PrendasService.NuevaPrenda PANTALON = new PrendasService.NuevaPrenda(
            Tipo.PANTALON, null, Patron.LISO, null, null, AZUL);

    private final PrendaRepository prendas = mock(PrendaRepository.class);
    private final CorreccionClasificacionRepository correcciones = mock(CorreccionClasificacionRepository.class);
    private final AlmacenImagenes imagenes = mock(AlmacenImagenes.class);
    private final ImagenesProperties config =
            new ImagenesProperties("bucket", null, null, null, null, null, 64, 15);

    private PrendasService servicio;

    @BeforeEach
    void preparar() {
        servicio = new PrendasService(prendas, correcciones, imagenes, config, Clock.fixed(AHORA, ZoneOffset.UTC));
        when(prendas.save(any(Prenda.class))).thenAnswer(i -> i.getArgument(0));
        when(prendas.findById(anyString())).thenReturn(Optional.empty());
    }

    @Test
    void guardarCompletaLoDeducidoYSubeLaImagenAntesQueElDocumento() {
        var guardado = servicio.guardar(SUB, ID, PANTALON, PNG);

        assertThat(guardado.creada()).isTrue();
        Prenda prenda = guardado.prenda();
        assertThat(prenda.usuarioId()).isEqualTo(SUB);
        assertThat(prenda.slotOutfit()).isEqualTo(SlotOutfit.TORSO_INFERIOR);
        assertThat(prenda.atributos().textura()).isEqualTo(Textura.DENIM);
        assertThat(prenda.atributos().climaApto()).containsExactly(Clima.FRIO, Clima.TEMPLADO);
        assertThat(prenda.imagenKey()).isEqualTo("usuarios/sub-ana/prendas/" + ID + ".png");
        assertThat(prenda.versionEsquema()).isEqualTo(1);
        assertThat(prenda.creadoEn()).isEqualTo(AHORA);

        var orden = inOrder(imagenes, prendas);
        orden.verify(imagenes).guardar(prenda.imagenKey(), PNG);
        orden.verify(prendas).save(any());
    }

    @Test
    void reintentarLaSubidaReemplazaSinDuplicarYConservaLaFechaDeCreacion() {
        Instant antes = AHORA.minusSeconds(3600);
        Prenda previa = new Prenda(ID, SUB, SlotOutfit.TORSO_INFERIOR, null, "clave", 1, antes, antes);
        when(prendas.findById(ID)).thenReturn(Optional.of(previa));

        var guardado = servicio.guardar(SUB, ID, PANTALON, PNG);

        assertThat(guardado.creada()).isFalse();
        assertThat(guardado.prenda().creadoEn()).isEqualTo(antes);
        assertThat(guardado.prenda().actualizadoEn()).isEqualTo(AHORA);
    }

    @Test
    void unIdDeOtroUsuarioNoSePisa() {
        Prenda ajena = new Prenda(ID, "otro", SlotOutfit.TORSO_INFERIOR, null, "clave", 1, AHORA, AHORA);
        when(prendas.findById(ID)).thenReturn(Optional.of(ajena));

        assertThatThrownBy(() -> servicio.guardar(SUB, ID, PANTALON, PNG))
                .isInstanceOf(ReglaDeNegocioException.class);
        verify(imagenes, never()).guardar(anyString(), any());
        verify(prendas, never()).save(any());
    }

    @Test
    void elIdTieneQueSerUnUuid() {
        assertThatThrownBy(() -> servicio.guardar(SUB, "../otra-cosa", PANTALON, PNG))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    @Test
    void laImagenTieneQueSerUnPngDentroDelTope() {
        assertThatThrownBy(() -> servicio.guardar(SUB, ID, PANTALON, new byte[] {1, 2, 3, 4, 5, 6, 7, 8, 9}))
                .isInstanceOf(ReglaDeNegocioException.class);
        byte[] grande = new byte[65];
        System.arraycopy(PNG, 0, grande, 0, 8);
        assertThatThrownBy(() -> servicio.guardar(SUB, ID, PANTALON, grande))
                .isInstanceOf(ReglaDeNegocioException.class);
        verify(imagenes, never()).guardar(anyString(), any());
    }

    @Test
    void obtenerLaDeOtroUsuarioEsNoEncontrada() {
        Prenda ajena = new Prenda(ID, "otro", SlotOutfit.TORSO_INFERIOR, null, "clave", 1, AHORA, AHORA);
        when(prendas.findById(ID)).thenReturn(Optional.of(ajena));

        assertThatThrownBy(() -> servicio.obtener(SUB, ID)).isInstanceOf(RecursoNoEncontradoException.class);
    }

    @Test
    void borrarEliminaPrimeroLaImagenYDespuesElDocumentoDelUsuario() {
        Prenda previa = guardada(Tipo.PANTALON, Textura.DENIM);
        when(prendas.findById(ID)).thenReturn(Optional.of(previa));

        servicio.borrar(SUB, ID);

        var orden = inOrder(imagenes, prendas);
        orden.verify(imagenes).borrar(List.of(previa.imagenKey()));
        orden.verify(prendas).deleteByIdAndUsuarioId(ID, SUB);
    }

    @Test
    void borrarUnaPrendaAjenaNoTocaLaImagenNiElDocumento() {
        Prenda previa = guardada(Tipo.PANTALON, Textura.DENIM);
        when(prendas.findById(ID)).thenReturn(Optional.of(previa));

        assertThatThrownBy(() -> servicio.borrar("otro", ID))
                .isInstanceOf(RecursoNoEncontradoException.class);

        verify(imagenes, never()).borrar(any());
        verify(prendas, never()).deleteByIdAndUsuarioId(anyString(), anyString());
    }

    @Test
    void borrarConElAlmacenCaidoConservaElDocumentoParaReintentar() {
        Prenda previa = guardada(Tipo.PANTALON, Textura.DENIM);
        when(prendas.findById(ID)).thenReturn(Optional.of(previa));
        doThrow(new IllegalStateException("sin almacen")).when(imagenes).borrar(List.of(previa.imagenKey()));

        assertThatThrownBy(() -> servicio.borrar(SUB, ID)).isInstanceOf(IllegalStateException.class);

        verify(prendas, never()).deleteByIdAndUsuarioId(anyString(), anyString());
    }

    @Test
    void corregirLaCategoriaDeColorLaRegistraSinUsuarioNiImagen() {
        when(prendas.findById(ID)).thenReturn(Optional.of(guardada(Tipo.PANTALON, Textura.DENIM)));

        Prenda corregida = servicio.corregir(SUB, ID, correccionCategoria(CategoriaColor.AZUL_MARINO));

        assertThat(corregida.atributos().color().categoria()).isEqualTo(CategoriaColor.AZUL_MARINO);
        var captor = ArgumentCaptor.forClass(CorreccionClasificacion.class);
        verify(correcciones).save(captor.capture());
        assertThat(captor.getValue().lab()).isEqualTo(AZUL.lab());
        assertThat(captor.getValue().categoriaConfirmada()).isEqualTo(CategoriaColor.AZUL_MARINO);
        assertThat(captor.getValue().creadoEn()).isEqualTo(AHORA);
    }

    @Test
    void confirmarLaMismaCategoriaNoRegistraNada() {
        when(prendas.findById(ID)).thenReturn(Optional.of(guardada(Tipo.PANTALON, Textura.DENIM)));

        servicio.corregir(SUB, ID, correccionCategoria(CategoriaColor.AZUL));

        verify(correcciones, never()).save(any());
    }

    @Test
    void corregirLaTexturaRecalculaFormalidadYClima() {
        when(prendas.findById(ID)).thenReturn(Optional.of(guardada(Tipo.PANTALON, Textura.DENIM)));

        Prenda corregida = servicio.corregir(SUB, ID,
                new PrendasService.Correccion(null, null, null, Textura.LISO_LIGERO, null, null));

        assertThat(corregida.atributos().textura()).isEqualTo(Textura.LISO_LIGERO);
        assertThat(corregida.atributos().climaApto()).containsExactly(Clima.TEMPLADO, Clima.CALIDO);
        assertThat(corregida.atributos().formalidad()).isEqualTo(RangoFormalidad.de(Formalidad.CASUAL));
    }

    @Test
    void corregirElTipoCambiaElSlotYQuitaLaTexturaSiYaNoAplica() {
        when(prendas.findById(ID)).thenReturn(Optional.of(guardada(Tipo.PANTALON, Textura.DENIM)));

        Prenda corregida = servicio.corregir(SUB, ID,
                new PrendasService.Correccion(Tipo.CALZADO, SubtipoCalzado.BOTAS, null, null, null, null));

        assertThat(corregida.slotOutfit()).isEqualTo(SlotOutfit.CALZADO);
        assertThat(corregida.atributos().textura()).isNull();
        assertThat(corregida.atributos().subtipoCalzado()).isEqualTo(SubtipoCalzado.BOTAS);
        assertThat(corregida.atributos().climaApto()).containsExactly(Clima.FRIO, Clima.TEMPLADO);
    }

    @Test
    void unaFormalidadEditadaSeConservaSiNoCambiaLoQueLaDecide() {
        Prenda previa = guardada(Tipo.CAMISA, Textura.LISO_LIGERO);
        var editada = new RangoFormalidad(Formalidad.CASUAL, Formalidad.FORMAL);
        previa = new Prenda(previa.id(), SUB, previa.slotOutfit(), new Atributos(Tipo.CAMISA, null, Patron.LISO,
                Textura.LISO_LIGERO, editada, previa.atributos().climaApto(), AZUL), previa.imagenKey(), 1,
                previa.creadoEn(), previa.actualizadoEn());
        when(prendas.findById(ID)).thenReturn(Optional.of(previa));

        Prenda corregida = servicio.corregir(SUB, ID,
                new PrendasService.Correccion(null, null, Patron.RAYAS, null, null, null));

        assertThat(corregida.atributos().patron()).isEqualTo(Patron.RAYAS);
        assertThat(corregida.atributos().formalidad()).isEqualTo(editada);
        assertThat(corregida.creadoEn()).isEqualTo(previa.creadoEn());
    }

    @Test
    void borrarTodoBorraImagenesYDocumentos() {
        Prenda una = guardada(Tipo.PANTALON, Textura.DENIM);
        when(prendas.findByUsuarioIdOrderByCreadoEnDesc(SUB)).thenReturn(List.of(una));

        servicio.borrarTodoDe(SUB);

        verify(imagenes).borrar(List.of(una.imagenKey()));
        verify(prendas).deleteByUsuarioId(SUB);
    }

    @Test
    void borrarSinPrendasNoLlamaAS3() {
        when(prendas.findByUsuarioIdOrderByCreadoEnDesc(SUB)).thenReturn(List.of());

        servicio.borrarTodoDe(SUB);

        verify(imagenes, never()).borrar(any());
        verify(prendas).deleteByUsuarioId(SUB);
    }

    private static Prenda guardada(Tipo tipo, Textura textura) {
        Atributos atributos = ReglasPrenda.completar(tipo, null, Patron.LISO, textura, null, AZUL);
        Instant creada = AHORA.minusSeconds(60);
        return new Prenda(ID, SUB, tipo.slot(), atributos, PrendasService.claveImagen(SUB, ID), 1, creada, creada);
    }

    private static PrendasService.Correccion correccionCategoria(CategoriaColor categoria) {
        return new PrendasService.Correccion(null, null, null, null, null, categoria);
    }
}
