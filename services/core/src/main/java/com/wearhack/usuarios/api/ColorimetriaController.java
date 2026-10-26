package com.wearhack.usuarios.api;

import com.wearhack.usuarios.colorimetria.Consentimiento;
import com.wearhack.usuarios.colorimetria.DerechosColorimetriaService;
import com.wearhack.usuarios.colorimetria.Finalidad;
import com.wearhack.usuarios.colorimetria.Lab;
import com.wearhack.usuarios.colorimetria.PerfilColorimetria;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Derechos sobre el perfil de colorimetria: consultar, borrar y revocar el consentimiento
 * (politica de datos, seccion 7). Como en {@link PerfilController}, el usuario siempre es el
 * del token.
 */
@RestController
@RequestMapping("/api/v1/usuarios/me")
class ColorimetriaController {

    private final DerechosColorimetriaService derechos;

    ColorimetriaController(DerechosColorimetriaService derechos) {
        this.derechos = derechos;
    }

    @GetMapping("/colorimetria")
    PerfilColorimetriaRespuesta perfil(@AuthenticationPrincipal Jwt token) {
        return PerfilColorimetriaRespuesta.de(derechos.perfil(token.getSubject()));
    }

    /** Borra el perfil derivado. Idempotente: sin perfil tambien responde 204. */
    @DeleteMapping("/colorimetria")
    ResponseEntity<Void> borrarPerfil(@AuthenticationPrincipal Jwt token) {
        derechos.borrarPerfil(token.getSubject());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/consentimientos")
    List<ConsentimientoRespuesta> consentimientos(@AuthenticationPrincipal Jwt token) {
        return derechos.consentimientos(token.getSubject()).stream()
                .map(ConsentimientoRespuesta::de)
                .toList();
    }

    /** Lo llama el cliente cuando el usuario pulsa "Autorizo". 201 si es nuevo, 200 si ya estaba. */
    @PostMapping("/consentimientos")
    ResponseEntity<ConsentimientoRespuesta> otorgar(
            @AuthenticationPrincipal Jwt token, @Valid @RequestBody SolicitudConsentimiento solicitud) {
        var otorgamiento = derechos.otorgar(
                token.getSubject(), Finalidad.desde(solicitud.finalidad()), solicitud.versionTexto());
        return ResponseEntity.status(otorgamiento.creado() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(ConsentimientoRespuesta.de(otorgamiento.consentimiento()));
    }

    /** Revoca y borra lo derivado. 404 si no habia un consentimiento vigente. */
    @DeleteMapping("/consentimientos/{finalidad}")
    ResponseEntity<Void> revocar(@AuthenticationPrincipal Jwt token, @PathVariable String finalidad) {
        derechos.revocar(token.getSubject(), Finalidad.desde(finalidad));
        return ResponseEntity.noContent().build();
    }

    /**
     * @param versionTexto la version del texto que vio el usuario. Si cambia, hay que volver
     *     a pedir el consentimiento
     */
    record SolicitudConsentimiento(
            @NotBlank @Pattern(regexp = "colorimetria", message = "finalidad desconocida") String finalidad,
            @NotBlank @Size(max = 40) String versionTexto) {}

    record ConsentimientoRespuesta(
            String id,
            String finalidad,
            String versionTexto,
            String estado,
            Instant otorgadoEn,
            Instant revocadoEn) {

        static ConsentimientoRespuesta de(Consentimiento consentimiento) {
            return new ConsentimientoRespuesta(
                    consentimiento.id(),
                    consentimiento.finalidad(),
                    consentimiento.versionTexto(),
                    consentimiento.estado(),
                    consentimiento.otorgadoEn(),
                    consentimiento.revocadoEn());
        }
    }

    record PerfilColorimetriaRespuesta(
            String temporada,
            Double confianza,
            Lab piel,
            Lab cabello,
            Lab iris,
            List<String> ejes,
            Instant calculadoEn) {

        static PerfilColorimetriaRespuesta de(PerfilColorimetria perfil) {
            return new PerfilColorimetriaRespuesta(
                    perfil.temporada(),
                    perfil.confianza(),
                    perfil.piel(),
                    perfil.cabello(),
                    perfil.iris(),
                    perfil.ejes(),
                    perfil.calculadoEn());
        }
    }
}
