package com.wearhack.closet.api;

import com.wearhack.closet.prendas.CategoriaColor;
import com.wearhack.closet.prendas.Clima;
import com.wearhack.closet.prendas.ColorPrenda;
import com.wearhack.closet.prendas.Formalidad;
import com.wearhack.closet.prendas.Patron;
import com.wearhack.closet.prendas.Prenda;
import com.wearhack.closet.prendas.PrendasService;
import com.wearhack.closet.prendas.PrendasService.Correccion;
import com.wearhack.closet.prendas.PrendasService.Guardado;
import com.wearhack.closet.prendas.PrendasService.NuevaPrenda;
import com.wearhack.closet.prendas.RangoFormalidad;
import com.wearhack.closet.prendas.SubtipoCalzado;
import com.wearhack.closet.prendas.Textura;
import com.wearhack.closet.prendas.Tipo;
import com.wearhack.plataforma.ReglaDeNegocioException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Las prendas del closet del usuario del token (issue #25).
 *
 * <p>Se crean con {@code PUT} y el id que genera el dispositivo: la cola de subida reintenta, y
 * con un {@code POST} cada reintento podria duplicar la prenda.
 */
@RestController
@RequestMapping("/api/v1/closet/me/prendas")
class PrendasController {

    private final PrendasService prendas;

    PrendasController(PrendasService prendas) {
        this.prendas = prendas;
    }

    /**
     * 201 si la crea, 200 si ya existia (un reintento) y la reemplaza. 422 si los atributos no son
     * coherentes, la imagen no es un PNG o el id no es un UUID.
     *
     * <p>La imagen va en base64 dentro del JSON y no como multipart: multipart la escribiria en un
     * archivo temporal del contenedor, y no hace falta para unos cientos de KB.
     */
    @PutMapping("/{id}")
    ResponseEntity<PrendaRespuesta> guardar(@AuthenticationPrincipal Jwt token, @PathVariable String id,
            @Valid @RequestBody SolicitudPrenda solicitud) {
        Guardado guardado = prendas.guardar(token.getSubject(), id, solicitud.aNuevaPrenda(),
                decodificar(solicitud.imagenPng()));
        return ResponseEntity.status(guardado.creada() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(respuesta(guardado.prenda()));
    }

    /** El closet entero, de la mas reciente a la mas vieja, con URLs firmadas de la imagen. */
    @GetMapping
    ClosetRespuesta listar(@AuthenticationPrincipal Jwt token) {
        return new ClosetRespuesta(prendas.listar(token.getSubject()).stream().map(this::respuesta).toList());
    }

    /** 404 si no existe o es de otro usuario. */
    @GetMapping("/{id}")
    PrendaRespuesta obtener(@AuthenticationPrincipal Jwt token, @PathVariable String id) {
        return respuesta(prendas.obtener(token.getSubject(), id));
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> borrar(@AuthenticationPrincipal Jwt token, @PathVariable String id) {
        prendas.borrar(token.getSubject(), id);
        return ResponseEntity.noContent().build();
    }

    /** Correcciones de la pantalla de revision. Solo cambia lo que venga. */
    @PatchMapping("/{id}")
    PrendaRespuesta corregir(@AuthenticationPrincipal Jwt token, @PathVariable String id,
            @RequestBody SolicitudCorreccion solicitud) {
        Correccion correccion = new Correccion(solicitud.tipo(), solicitud.subtipoCalzado(), solicitud.patron(),
                solicitud.textura(), aRango(solicitud.formalidad()), solicitud.categoriaColor());
        return respuesta(prendas.corregir(token.getSubject(), id, correccion));
    }

    private PrendaRespuesta respuesta(Prenda prenda) {
        return PrendaRespuesta.de(prenda, prendas.urlImagen(prenda));
    }

    private static byte[] decodificar(String base64) {
        try {
            return Base64.getDecoder().decode(base64);
        } catch (IllegalArgumentException e) {
            throw new ReglaDeNegocioException("La imagen no es base64 valido");
        }
    }

    private static RangoFormalidad aRango(FormalidadDto dto) {
        return dto == null ? null : new RangoFormalidad(dto.min(), dto.max());
    }

    record FormalidadDto(Formalidad min, Formalidad max) {

        static FormalidadDto de(RangoFormalidad rango) {
            return rango == null ? null : new FormalidadDto(rango.min(), rango.max());
        }
    }

    record ColorDto(@NotNull List<Double> lab, @NotNull CategoriaColor categoria) {}

    /**
     * @param textura opcional: sin ella va la de por defecto del tipo. Calzado y accesorios no llevan
     * @param formalidad opcional: sin ella va la de por defecto del tipo y la textura
     * @param imagenPng la prenda sin fondo, PNG en base64
     */
    record SolicitudPrenda(
            @NotNull Tipo tipo,
            SubtipoCalzado subtipoCalzado,
            @NotNull Patron patron,
            Textura textura,
            FormalidadDto formalidad,
            @NotNull @Valid ColorDto color,
            @NotBlank String imagenPng) {

        NuevaPrenda aNuevaPrenda() {
            return new NuevaPrenda(tipo, subtipoCalzado, patron, textura, aRango(formalidad),
                    new ColorPrenda(color.lab(), color.categoria()));
        }
    }

    record SolicitudCorreccion(
            Tipo tipo,
            SubtipoCalzado subtipoCalzado,
            Patron patron,
            Textura textura,
            FormalidadDto formalidad,
            CategoriaColor categoriaColor) {}

    record ClosetRespuesta(List<PrendaRespuesta> prendas) {}

    record PrendaRespuesta(
            String id,
            String slotOutfit,
            Tipo tipo,
            SubtipoCalzado subtipoCalzado,
            Patron patron,
            Textura textura,
            FormalidadDto formalidad,
            List<Clima> climaApto,
            ColorDto color,
            String imagenUrl,
            Instant creadoEn,
            Instant actualizadoEn) {

        static PrendaRespuesta de(Prenda prenda, String imagenUrl) {
            var a = prenda.atributos();
            return new PrendaRespuesta(prenda.id(), prenda.slotOutfit().name(), a.tipo(), a.subtipoCalzado(),
                    a.patron(), a.textura(), FormalidadDto.de(a.formalidad()), a.climaApto(),
                    new ColorDto(a.color().lab(), a.color().categoria()), imagenUrl,
                    prenda.creadoEn(), prenda.actualizadoEn());
        }
    }
}
