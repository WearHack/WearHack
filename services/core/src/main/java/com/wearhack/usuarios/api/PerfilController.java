package com.wearhack.usuarios.api;

import com.wearhack.usuarios.Plan;
import com.wearhack.usuarios.perfil.PerfilService;
import com.wearhack.usuarios.perfil.Usuario;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * El perfil del usuario autenticado.
 *
 * <p>Todas las rutas son {@code /me}: el usuario sale del {@code sub} del token, nunca de
 * la ruta ni del cuerpo. No hay forma de pedir los datos de otra persona.
 */
@RestController
@RequestMapping("/api/v1/usuarios/me")
class PerfilController {

    private final PerfilService perfiles;

    PerfilController(PerfilService perfiles) {
        this.perfiles = perfiles;
    }

    @GetMapping
    PerfilRespuesta obtener(@AuthenticationPrincipal Jwt token) {
        return PerfilRespuesta.de(perfiles.obtener(token.getSubject()));
    }

    /**
     * Completa el registro despues del de Cognito (201) o actualiza el perfil (200).
     * Crear exige {@code mayorDeEdad: true}.
     */
    @PutMapping
    ResponseEntity<PerfilRespuesta> registrar(
            @AuthenticationPrincipal Jwt token, @Valid @RequestBody SolicitudPerfil solicitud) {
        var registro = perfiles.registrar(token.getSubject(), solicitud.nombre(), solicitud.mayorDeEdad());
        return ResponseEntity.status(registro.creado() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(PerfilRespuesta.de(registro.usuario()));
    }

    /** Elimina la cuenta entera, incluida la de Cognito. Se puede reintentar. */
    @DeleteMapping
    ResponseEntity<Void> eliminar(@AuthenticationPrincipal Jwt token) {
        // En una cuenta federada (Google) el username de Cognito no es el sub.
        String nombreUsuario = token.hasClaim("username")
                ? token.getClaimAsString("username")
                : token.getSubject();
        perfiles.eliminarCuenta(token.getSubject(), nombreUsuario);
        return ResponseEntity.noContent().build();
    }

    /**
     * @param mayorDeEdad la casilla de mayoria de edad del registro. Obligatoria para crear
     */
    record SolicitudPerfil(@Size(max = 80) String nombre, Boolean mayorDeEdad) {}

    record PerfilRespuesta(
            String id,
            String nombre,
            boolean mayorDeEdad,
            Instant mayoriaEdadDeclaradaEn,
            Instant creadoEn,
            Instant actualizadoEn,
            Plan plan) {

        static PerfilRespuesta de(Usuario usuario) {
            return new PerfilRespuesta(
                    usuario.id(),
                    usuario.nombre(),
                    usuario.mayoriaEdadDeclaradaEn() != null,
                    usuario.mayoriaEdadDeclaradaEn(),
                    usuario.creadoEn(),
                    usuario.actualizadoEn(),
                    usuario.planVigente());
        }
    }
}
