package com.wearhack.usuarios.colorimetria;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.usuarios.perfil.UsuarioRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** Consentimiento y derechos sobre el perfil de color (issue #56). */
class DerechosColorimetriaServiceTest {

    private static final String SUB = "sub-ana";
    private static final Instant AHORA = Instant.parse("2026-10-15T12:00:00Z");

    private final ConsentimientoRepository consentimientos = mock(ConsentimientoRepository.class);
    private final PerfilColorimetriaRepository perfiles = mock(PerfilColorimetriaRepository.class);
    private final CorreccionColorimetriaRepository correcciones = mock(CorreccionColorimetriaRepository.class);
    private final UsuarioRepository usuarios = mock(UsuarioRepository.class);

    private DerechosColorimetriaService servicio;

    @BeforeEach
    void preparar() {
        servicio = new DerechosColorimetriaService(consentimientos, perfiles, correcciones, usuarios,
                Clock.fixed(AHORA, ZoneOffset.UTC));
        when(usuarios.existsById(SUB)).thenReturn(true);
        when(consentimientos.save(any(Consentimiento.class)))
                .thenAnswer(invocacion -> invocacion.getArgument(0));
    }

    @Test
    void otorgarRegistraVersionFechaYFinalidad() {
        sinVigente();

        var otorgamiento = servicio.otorgar(SUB, Finalidad.COLORIMETRIA, "2026-10-01");

        assertThat(otorgamiento.creado()).isTrue();
        Consentimiento nuevo = otorgamiento.consentimiento();
        assertThat(nuevo.usuarioId()).isEqualTo(SUB);
        assertThat(nuevo.finalidad()).isEqualTo("colorimetria");
        assertThat(nuevo.versionTexto()).isEqualTo("2026-10-01");
        assertThat(nuevo.estado()).isEqualTo(Consentimiento.OTORGADO);
        assertThat(nuevo.otorgadoEn()).isEqualTo(AHORA);
    }

    @Test
    void otorgarDosVecesLaMismaVersionNoDuplica() {
        Consentimiento vigente = vigente("2026-10-01");

        var otorgamiento = servicio.otorgar(SUB, Finalidad.COLORIMETRIA, "2026-10-01");

        assertThat(otorgamiento.creado()).isFalse();
        assertThat(otorgamiento.consentimiento()).isEqualTo(vigente);
        verify(consentimientos, never()).save(any());
    }

    @Test
    void unaVersionNuevaDelTextoSustituyeALaAnterior() {
        Consentimiento anterior = vigente("2026-10-01");

        var otorgamiento = servicio.otorgar(SUB, Finalidad.COLORIMETRIA, "2026-11-01");

        assertThat(otorgamiento.creado()).isTrue();
        verify(consentimientos).save(anterior.sustituido());
    }

    @Test
    void sinRegistroNoSePuedeOtorgar() {
        when(usuarios.existsById(SUB)).thenReturn(false);

        assertThatThrownBy(() -> servicio.otorgar(SUB, Finalidad.COLORIMETRIA, "v1"))
                .isInstanceOf(RecursoNoEncontradoException.class);
    }

    @Test
    void revocarCambiaElEstadoYBorraLoDerivado() {
        Consentimiento vigente = vigente("2026-10-01");

        servicio.revocar(SUB, Finalidad.COLORIMETRIA);

        verify(consentimientos).save(vigente.revocado(AHORA));
        verify(perfiles).deleteById(SUB);
        verify(correcciones).deleteByUsuarioId(SUB);
    }

    @Test
    void revocarSinConsentimientoVigenteEs404() {
        sinVigente();

        assertThatThrownBy(() -> servicio.revocar(SUB, Finalidad.COLORIMETRIA))
                .isInstanceOf(RecursoNoEncontradoException.class);
        verify(perfiles, never()).deleteById(any());
    }

    @Test
    void borrarElPerfilNoRevocaElConsentimiento() {
        servicio.borrarPerfil(SUB);

        verify(perfiles).deleteById(SUB);
        verify(consentimientos, never()).save(any());
    }

    @Test
    void laFinalidadDesconocidaNoExiste() {
        assertThatThrownBy(() -> Finalidad.desde("publicidad"))
                .isInstanceOf(RecursoNoEncontradoException.class);
    }

    private void sinVigente() {
        when(consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                SUB, "colorimetria", Consentimiento.OTORGADO)).thenReturn(Optional.empty());
    }

    private Consentimiento vigente(String version) {
        var consentimiento = new Consentimiento("c1", SUB, "colorimetria", version,
                Consentimiento.OTORGADO, AHORA.minusSeconds(3600), null);
        when(consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                SUB, "colorimetria", Consentimiento.OTORGADO)).thenReturn(Optional.of(consentimiento));
        return consentimiento;
    }
}
