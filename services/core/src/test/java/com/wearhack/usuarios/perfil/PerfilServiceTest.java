package com.wearhack.usuarios.perfil;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.wearhack.plataforma.ProveedorIdentidad;
import com.wearhack.plataforma.ProveedorIdentidadException;
import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.usuarios.CuentaEliminada;
import com.wearhack.usuarios.colorimetria.DerechosColorimetriaService;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.context.ApplicationEventPublisher;

/** Reglas del registro (issue #10) y de la eliminacion de la cuenta (issue #56). */
class PerfilServiceTest {

    private static final String SUB = "sub-ana";
    private static final Instant AHORA = Instant.parse("2026-10-15T12:00:00Z");

    private final UsuarioRepository usuarios = mock(UsuarioRepository.class);
    private final DerechosColorimetriaService colorimetria = mock(DerechosColorimetriaService.class);
    private final ProveedorIdentidad proveedor = mock(ProveedorIdentidad.class);
    private final ApplicationEventPublisher eventos = mock(ApplicationEventPublisher.class);

    private PerfilService servicio;

    @BeforeEach
    void preparar() {
        servicio = new PerfilService(usuarios, colorimetria, proveedor, eventos,
                Clock.fixed(AHORA, ZoneOffset.UTC));
        when(usuarios.save(any(Usuario.class))).thenAnswer(invocacion -> invocacion.getArgument(0));
    }

    @Test
    void registrarseExigeDeclararLaMayoriaDeEdad() {
        when(usuarios.findById(SUB)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> servicio.registrar(SUB, "Ana", null))
                .isInstanceOf(ReglaDeNegocioException.class);
        assertThatThrownBy(() -> servicio.registrar(SUB, "Ana", false))
                .isInstanceOf(ReglaDeNegocioException.class);
        verify(usuarios, never()).save(any());
    }

    @Test
    void alRegistrarseQuedaLaFechaDeLaDeclaracion() {
        when(usuarios.findById(SUB)).thenReturn(Optional.empty());

        var registro = servicio.registrar(SUB, "  Ana  ", true);

        assertThat(registro.creado()).isTrue();
        assertThat(registro.usuario().id()).isEqualTo(SUB);
        assertThat(registro.usuario().nombre()).isEqualTo("Ana");
        assertThat(registro.usuario().mayoriaEdadDeclaradaEn()).isEqualTo(AHORA);
    }

    @Test
    void actualizarNoCambiaLaFechaDeLaDeclaracion() {
        Instant antes = AHORA.minusSeconds(86_400);
        when(usuarios.findById(SUB)).thenReturn(Optional.of(new Usuario(SUB, "Ana", antes, antes, antes)));

        var registro = servicio.registrar(SUB, "Ana Maria", null);

        assertThat(registro.creado()).isFalse();
        assertThat(registro.usuario().nombre()).isEqualTo("Ana Maria");
        assertThat(registro.usuario().mayoriaEdadDeclaradaEn()).isEqualTo(antes);
        assertThat(registro.usuario().actualizadoEn()).isEqualTo(AHORA);
    }

    @Test
    void laDeclaracionNoSePuedeRetirar() {
        when(usuarios.findById(SUB)).thenReturn(Optional.of(new Usuario(SUB, null, AHORA, AHORA, AHORA)));

        assertThatThrownBy(() -> servicio.registrar(SUB, null, false))
                .isInstanceOf(ReglaDeNegocioException.class);
    }

    @Test
    void unUsuarioSinRegistrarNoTienePerfil() {
        when(usuarios.findById(SUB)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> servicio.obtener(SUB)).isInstanceOf(RecursoNoEncontradoException.class);
    }

    @Test
    void eliminarLaCuentaBorraLosDatosAntesQueLaCuentaDeCognito() {
        servicio.eliminarCuenta(SUB, "google_123");

        var orden = inOrder(colorimetria, usuarios, eventos, proveedor);
        orden.verify(colorimetria).borrarTodoDe(SUB);
        orden.verify(usuarios).deleteById(SUB);
        orden.verify(eventos).publishEvent(new CuentaEliminada(SUB));
        orden.verify(proveedor).eliminarCuenta("google_123");
    }

    @Test
    void siCognitoFallaElErrorSube() {
        // El usuario conserva el acceso y puede reintentar: los borrados de antes son idempotentes.
        doThrow(new ProveedorIdentidadException("caido", null)).when(proveedor).eliminarCuenta("ana");

        assertThatThrownBy(() -> servicio.eliminarCuenta(SUB, "ana"))
                .isInstanceOf(ProveedorIdentidadException.class);
        verify(usuarios).deleteById(SUB);
    }
}
