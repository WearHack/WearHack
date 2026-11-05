package com.wearhack.usuarios.colorimetria;

import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.plataforma.ReglaDeNegocioException;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * El usuario dice que su temporada es otra. Se guarda como correccion para la recalibracion
 * de centroides (issue #37).
 *
 * <p>Los colores salen del perfil guardado y no de la peticion: lo que se corrige es la
 * temporada, no lo que midio el servicio, y asi el cliente no puede inyectar colores.
 */
@Service
public class CorreccionesColorimetriaService {

    private final ConsentimientoRepository consentimientos;
    private final PerfilColorimetriaRepository perfiles;
    private final CorreccionColorimetriaRepository correcciones;
    private final Clock reloj;

    CorreccionesColorimetriaService(ConsentimientoRepository consentimientos,
            PerfilColorimetriaRepository perfiles, CorreccionColorimetriaRepository correcciones, Clock reloj) {
        this.consentimientos = consentimientos;
        this.perfiles = perfiles;
        this.correcciones = correcciones;
        this.reloj = reloj;
    }

    /** @param temporada una de {@link CorreccionColorimetria#TEMPORADAS}, sin importar mayusculas */
    public CorreccionColorimetria corregir(String usuarioId, String temporada) {
        String confirmada = temporada == null ? "" : temporada.trim().toUpperCase();
        if (!CorreccionColorimetria.TEMPORADAS.contains(confirmada)) {
            throw new ReglaDeNegocioException("Temporada desconocida: " + temporada);
        }
        // La correccion es un dato derivado del rostro: sin consentimiento no se guarda.
        boolean vigente = consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                usuarioId, Finalidad.COLORIMETRIA.valor(), Consentimiento.OTORGADO).isPresent();
        if (!vigente) {
            throw new ReglaDeNegocioException("Falta el consentimiento vigente para la colorimetria");
        }
        PerfilColorimetria perfil = perfiles.findById(usuarioId)
                .orElseThrow(() -> new RecursoNoEncontradoException(
                        "El usuario no tiene perfil de colorimetria que corregir"));

        return correcciones.save(new CorreccionColorimetria(
                UUID.randomUUID().toString(),
                usuarioId,
                perfil.piel(),
                perfil.cabello(),
                perfil.iris(),
                confirmada,
                Instant.now(reloj),
                null));
    }
}
