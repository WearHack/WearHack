package com.wearhack.usuarios.perfil;

import com.wearhack.plataforma.ProveedorIdentidad;
import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.usuarios.CuentaEliminada;
import com.wearhack.usuarios.colorimetria.DerechosColorimetriaService;
import java.time.Clock;
import java.time.Instant;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

/**
 * Registro, consulta y eliminacion de la cuenta de negocio.
 *
 * <p>El registro de credenciales ya paso en Cognito. Aqui solo se crea el perfil ligado al
 * {@code sub} y se deja constancia de la declaracion de mayoria de edad: el MVP es solo
 * para mayores de 18 (politica de datos, seccion 9).
 */
@Service
public class PerfilService {

    private final UsuarioRepository usuarios;
    private final DerechosColorimetriaService colorimetria;
    private final ProveedorIdentidad proveedorIdentidad;
    private final ApplicationEventPublisher eventos;
    private final Clock reloj;

    PerfilService(
            UsuarioRepository usuarios,
            DerechosColorimetriaService colorimetria,
            ProveedorIdentidad proveedorIdentidad,
            ApplicationEventPublisher eventos,
            Clock reloj) {
        this.usuarios = usuarios;
        this.colorimetria = colorimetria;
        this.proveedorIdentidad = proveedorIdentidad;
        this.eventos = eventos;
        this.reloj = reloj;
    }

    /** Resultado de {@link #registrar}: el perfil y si se acaba de crear. */
    public record Registro(Usuario usuario, boolean creado) {}

    public Usuario obtener(String usuarioId) {
        return usuarios.findById(usuarioId)
                .orElseThrow(() -> new RecursoNoEncontradoException(
                        "El usuario no ha completado el registro"));
    }

    /**
     * Crea el perfil o actualiza el nombre.
     *
     * <p>Para crearlo hay que declarar la mayoria de edad. Despues la declaracion no se
     * puede retirar: quien deja de cumplirla elimina la cuenta, no la desmarca.
     *
     * @param mayorDeEdad la casilla del registro. En una actualizacion puede omitirse
     */
    public Registro registrar(String usuarioId, String nombre, Boolean mayorDeEdad) {
        Instant ahora = Instant.now(reloj);
        String nombreLimpio = nombre == null || nombre.isBlank() ? null : nombre.strip();

        return usuarios.findById(usuarioId)
                .map(existente -> {
                    if (Boolean.FALSE.equals(mayorDeEdad)) {
                        throw new ReglaDeNegocioException("La declaracion de mayoria de edad no se "
                                + "puede retirar: para dejar el servicio, elimina la cuenta");
                    }
                    return new Registro(usuarios.save(existente.conNombre(nombreLimpio, ahora)), false);
                })
                .orElseGet(() -> {
                    if (!Boolean.TRUE.equals(mayorDeEdad)) {
                        throw new ReglaDeNegocioException(
                                "WearHack es solo para mayores de 18: hay que declarar la mayoria de edad");
                    }
                    Usuario nuevo = new Usuario(usuarioId, nombreLimpio, ahora, ahora, ahora);
                    return new Registro(usuarios.save(nuevo), true);
                });
    }

    /**
     * Elimina la cuenta entera: los datos de este modulo, la cuenta de Cognito y, por el
     * evento {@link CuentaEliminada}, lo que otros modulos tengan del usuario.
     *
     * <p>Primero se borran los datos y al final la cuenta de Cognito. Si Cognito falla, el
     * usuario conserva el acceso y puede reintentar: cada paso es idempotente. Al reves,
     * un fallo dejaria datos huerfanos de una cuenta que ya no puede pedir que se borren.
     *
     * @param nombreUsuario el claim {@code username} del token, que Cognito necesita para
     *     borrar la cuenta
     */
    public void eliminarCuenta(String usuarioId, String nombreUsuario) {
        colorimetria.borrarTodoDe(usuarioId);
        usuarios.deleteById(usuarioId);
        eventos.publishEvent(new CuentaEliminada(usuarioId));
        proveedorIdentidad.eliminarCuenta(nombreUsuario);
    }
}
