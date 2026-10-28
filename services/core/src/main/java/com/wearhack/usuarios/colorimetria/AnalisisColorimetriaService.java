package com.wearhack.usuarios.colorimetria;

import com.wearhack.plataforma.ReglaDeNegocioException;
import java.time.Clock;
import java.time.Instant;
import org.springframework.stereotype.Service;

/** Recibe el recorte, comprueba el consentimiento, lo reenvia a Colorimetria y guarda solo lo derivado. */
@Service
public class AnalisisColorimetriaService {

    private static final byte[] FIRMA_PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};

    private final ConsentimientoRepository consentimientos;
    private final PerfilColorimetriaRepository perfiles;
    private final ClienteColorimetria ia;
    private final Clock reloj;

    AnalisisColorimetriaService(ConsentimientoRepository consentimientos,
            PerfilColorimetriaRepository perfiles, ClienteColorimetria ia, Clock reloj) {
        this.consentimientos = consentimientos;
        this.perfiles = perfiles;
        this.ia = ia;
        this.reloj = reloj;
    }

    public PerfilColorimetria analizar(String usuarioId, byte[] recorte) {
        if (!esPng(recorte)) {
            throw new ReglaDeNegocioException("El recorte debe ser un PNG");
        }
        exigirConsentimiento(usuarioId);
        ResultadoColorimetria r = ia.analizar(recorte);
        // Pudo revocar durante la llamada (hasta 10 s). No es atomico, pero reduce la ventana.
        exigirConsentimiento(usuarioId);
        return perfiles.save(new PerfilColorimetria(usuarioId, r.piel(), r.cabello(), r.iris(),
                r.ejes(), r.temporada(), r.confianza(), Instant.now(reloj)));
    }

    private void exigirConsentimiento(String usuarioId) {
        boolean vigente = consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                usuarioId, Finalidad.COLORIMETRIA.valor(), Consentimiento.OTORGADO).isPresent();
        if (!vigente) {
            throw new ReglaDeNegocioException("Falta el consentimiento vigente para la colorimetria");
        }
    }

    private static boolean esPng(byte[] bytes) {
        if (bytes == null || bytes.length <= FIRMA_PNG.length) return false;
        for (int i = 0; i < FIRMA_PNG.length; i++) {
            if (bytes[i] != FIRMA_PNG[i]) return false;
        }
        return true;
    }
}
