package com.wearhack.usuarios.api;

import com.wearhack.usuarios.colorimetria.CorreccionColorimetria;
import com.wearhack.usuarios.colorimetria.CorreccionesColorimetriaService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** El usuario corrige la temporada de su perfil de colorimetria. Como siempre, el usuario es el del token. */
@RestController
@RequestMapping("/api/v1/usuarios/me/colorimetria")
class CorreccionesController {

    private final CorreccionesColorimetriaService correcciones;

    CorreccionesController(CorreccionesColorimetriaService correcciones) {
        this.correcciones = correcciones;
    }

    /** 201 con la correccion. 422 sin consentimiento o con una temporada desconocida; 404 sin perfil. */
    @PostMapping("/correcciones")
    @ResponseStatus(HttpStatus.CREATED)
    CorreccionRespuesta corregir(@AuthenticationPrincipal Jwt token, @Valid @RequestBody SolicitudCorreccion solicitud) {
        return CorreccionRespuesta.de(correcciones.corregir(token.getSubject(), solicitud.temporada()));
    }

    /** @param temporada PRIMAVERA, VERANO, OTONO o INVIERNO */
    record SolicitudCorreccion(@NotBlank String temporada) {}

    record CorreccionRespuesta(String id, String temporadaConfirmada, Instant creadaEn) {

        static CorreccionRespuesta de(CorreccionColorimetria correccion) {
            return new CorreccionRespuesta(
                    correccion.id(), correccion.temporadaConfirmada(), correccion.creadaEn());
        }
    }
}
