package com.wearhack.usuarios.colorimetria;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class AnalisisColorimetriaServiceTest {

    private static final String SUB = "sub-ana";
    private static final Instant AHORA = Instant.parse("2026-10-15T12:00:00Z");
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3};
    private static final Consentimiento VIGENTE = new Consentimiento(
            "c1", SUB, "colorimetria", "v1", Consentimiento.OTORGADO, AHORA, null);

    private final ConsentimientoRepository consentimientos = mock(ConsentimientoRepository.class);
    private final PerfilColorimetriaRepository perfiles = mock(PerfilColorimetriaRepository.class);
    private final ClienteColorimetria ia = mock(ClienteColorimetria.class);
    private AnalisisColorimetriaService servicio;

    @BeforeEach
    void preparar() {
        servicio = new AnalisisColorimetriaService(consentimientos, perfiles, ia,
                Clock.fixed(AHORA, ZoneOffset.UTC));
        when(perfiles.save(any(PerfilColorimetria.class))).thenAnswer(i -> i.getArgument(0));
    }

    private void consentimiento(Optional<Consentimiento> valor) {
        when(consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                SUB, "colorimetria", Consentimiento.OTORGADO)).thenReturn(valor);
    }

    @Test
    void sinConsentimientoNoSeLlamaALaIa() {
        consentimiento(Optional.empty());

        assertThatThrownBy(() -> servicio.analizar(SUB, PNG)).isInstanceOf(ReglaDeNegocioException.class);
        verifyNoInteractions(ia);
        verify(perfiles, never()).save(any());
    }

    @Test
    void loQueNoEsUnPngNoLlegaALaIa() {
        consentimiento(Optional.of(VIGENTE));

        assertThatThrownBy(() -> servicio.analizar(SUB, new byte[] {1, 2, 3, 4, 5, 6, 7, 8, 9}))
                .isInstanceOf(ReglaDeNegocioException.class);
        verifyNoInteractions(ia);
    }

    @Test
    void guardaSoloLosValoresDerivados() {
        consentimiento(Optional.of(VIGENTE));
        when(ia.analizar(PNG)).thenReturn(new ResultadoColorimetria("otono", 0.82,
                List.of("piel", "iris"), new Lab(62.1, 14.3, 18.9), null, new Lab(35.5, 2.0, 12.4)));

        PerfilColorimetria perfil = servicio.analizar(SUB, PNG);

        assertThat(perfil.usuarioId()).isEqualTo(SUB);
        assertThat(perfil.piel()).isEqualTo(new Lab(62.1, 14.3, 18.9));
        assertThat(perfil.cabello()).as("sin cabello no se imputa nada").isNull();
        assertThat(perfil.ejes()).containsExactly("piel", "iris");
        assertThat(perfil.calculadoEn()).isEqualTo(AHORA);
    }

    @Test
    void siLaIaFallaNoSeGuardaNada() {
        consentimiento(Optional.of(VIGENTE));
        when(ia.analizar(PNG)).thenThrow(new ServicioIaNoDisponibleException("caida", null));

        assertThatThrownBy(() -> servicio.analizar(SUB, PNG)).isInstanceOf(ServicioIaNoDisponibleException.class);
        verify(perfiles, never()).save(any());
    }

    @Test
    void siRevocaMientrasLaIaTrabajaNoSeGuarda() {
        when(consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                SUB, "colorimetria", Consentimiento.OTORGADO))
                .thenReturn(Optional.of(VIGENTE)).thenReturn(Optional.empty());
        when(ia.analizar(PNG)).thenReturn(new ResultadoColorimetria("otono", 0.8, List.of("piel"),
                new Lab(60, 10, 15), null, null));

        assertThatThrownBy(() -> servicio.analizar(SUB, PNG)).isInstanceOf(ReglaDeNegocioException.class);
        verify(perfiles, never()).save(any());
    }
}