package com.wearhack.usuarios.colorimetria;

import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.usuarios.perfil.UsuarioRepository;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;

/**
 * Consentimiento y derechos sobre el perfil de colorimetria: consultar, borrar y revocar
 * (politica de datos, secciones 5 y 7).
 *
 * <p>La colorimetria es opcional. Nada de aqui es requisito para usar el resto de la app.
 */
@Service
public class DerechosColorimetriaService {

    private final ConsentimientoRepository consentimientos;
    private final PerfilColorimetriaRepository perfiles;
    private final CorreccionColorimetriaRepository correcciones;
    private final UsuarioRepository usuarios;
    private final Clock reloj;

    DerechosColorimetriaService(
            ConsentimientoRepository consentimientos,
            PerfilColorimetriaRepository perfiles,
            CorreccionColorimetriaRepository correcciones,
            UsuarioRepository usuarios,
            Clock reloj) {
        this.consentimientos = consentimientos;
        this.perfiles = perfiles;
        this.correcciones = correcciones;
        this.usuarios = usuarios;
        this.reloj = reloj;
    }

    /** Resultado de {@link #otorgar}: el consentimiento vigente y si se acaba de crear. */
    public record Otorgamiento(Consentimiento consentimiento, boolean creado) {}

    /**
     * Registra la autorizacion. Repetirla con la misma version no crea otra. Con una version
     * nueva del texto, la anterior queda sustituida: es el re-consentimiento que pide la
     * politica cuando cambia el texto.
     */
    public Otorgamiento otorgar(String usuarioId, Finalidad finalidad, String versionTexto) {
        if (!usuarios.existsById(usuarioId)) {
            throw new RecursoNoEncontradoException("El usuario no ha completado el registro");
        }
        var vigente = consentimientos.findFirstByUsuarioIdAndFinalidadAndEstado(
                usuarioId, finalidad.valor(), Consentimiento.OTORGADO);
        if (vigente.isPresent() && vigente.get().versionTexto().equals(versionTexto)) {
            return new Otorgamiento(vigente.get(), false);
        }
        vigente.ifPresent(anterior -> consentimientos.save(anterior.sustituido()));

        Consentimiento nuevo = new Consentimiento(
                UUID.randomUUID().toString(),
                usuarioId,
                finalidad.valor(),
                versionTexto,
                Consentimiento.OTORGADO,
                Instant.now(reloj),
                null);
        return new Otorgamiento(consentimientos.save(nuevo), true);
    }

    /** El historial completo, del mas reciente al mas antiguo, incluidos los revocados. */
    public List<Consentimiento> consentimientos(String usuarioId) {
        return consentimientos.findByUsuarioIdOrderByOtorgadoEnDesc(usuarioId);
    }

    /**
     * Revoca el consentimiento vigente. Con el se va todo lo que salio de el: el perfil
     * derivado y las correcciones que aun esten vinculadas. Las ya desvinculadas son datos
     * agregados y no se pueden atribuir a nadie.
     */
    public void revocar(String usuarioId, Finalidad finalidad) {
        Consentimiento vigente = consentimientos
                .findFirstByUsuarioIdAndFinalidadAndEstado(
                        usuarioId, finalidad.valor(), Consentimiento.OTORGADO)
                .orElseThrow(() -> new RecursoNoEncontradoException(
                        "No hay un consentimiento vigente para " + finalidad.valor()));

        consentimientos.save(vigente.revocado(Instant.now(reloj)));
        perfiles.deleteById(usuarioId);
        correcciones.deleteByUsuarioId(usuarioId);
    }

    public PerfilColorimetria perfil(String usuarioId) {
        return perfiles.findById(usuarioId)
                .orElseThrow(() -> new RecursoNoEncontradoException(
                        "El usuario no tiene perfil de colorimetria"));
    }

    /**
     * Borra el perfil derivado. El consentimiento sigue vigente: borrar el resultado no es
     * retirar la autorizacion, y el usuario puede volver a calcularlo.
     */
    public void borrarPerfil(String usuarioId) {
        perfiles.deleteById(usuarioId);
    }

    /** Todo lo de colorimetria de un usuario, para cuando elimina la cuenta. */
    public void borrarTodoDe(String usuarioId) {
        perfiles.deleteById(usuarioId);
        correcciones.deleteByUsuarioId(usuarioId);
        consentimientos.deleteByUsuarioId(usuarioId);
    }
}
