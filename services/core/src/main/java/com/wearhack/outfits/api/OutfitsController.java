package com.wearhack.outfits.api;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/outfits/me")
class OutfitsController {
    private final OutfitsService servicio;

    OutfitsController(OutfitsService servicio) {
        this.servicio = servicio;
    }

    record SolicitudHoy(@NotNull OutfitsService.Ocasion ocasion, OutfitsService.Mood mood,
            OutfitsService.Clima clima) {}
    record Eleccion(@NotBlank String loteId, @NotBlank String outfitId) {}
    record Asignacion(String outfitId) {}
    record Opciones(List<LoteOutfits.Opcion> outfits) {}
    record Semana(List<OutfitsService.Dia> dias) {}

    @PostMapping("/hoy")
    OutfitsService.Hoy hoy(@AuthenticationPrincipal Jwt token, @Valid @RequestBody SolicitudHoy contexto) {
        return servicio.opcionesHoy(token.getSubject(),
                new OutfitsService.Contexto(contexto.ocasion(), contexto.mood(), contexto.clima()));
    }

    @PostMapping("/hoy/eleccion")
    ResponseEntity<Void> elegir(@AuthenticationPrincipal Jwt token, @Valid @RequestBody Eleccion eleccion) {
        servicio.elegir(token.getSubject(), eleccion.loteId(), eleccion.outfitId());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/semana")
    Semana semana(@AuthenticationPrincipal Jwt token) {
        return new Semana(servicio.plan(token.getSubject()));
    }

    @PostMapping("/semana/outfits")
    Opciones opciones(@AuthenticationPrincipal Jwt token) {
        return new Opciones(servicio.opcionesSemana(token.getSubject()));
    }

    @PutMapping("/semana/{fecha}")
    ResponseEntity<Void> asignar(@AuthenticationPrincipal Jwt token,
            @PathVariable @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate fecha,
            @RequestBody Asignacion asignacion) {
        servicio.asignar(token.getSubject(), fecha, asignacion.outfitId());
        return ResponseEntity.noContent().build();
    }
}
