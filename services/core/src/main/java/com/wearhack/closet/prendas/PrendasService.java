package com.wearhack.closet.prendas;

import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.plataforma.ReglaDeNegocioException;
import java.time.Clock;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;

/**
 * Guardar, consultar y corregir prendas. Siempre las del usuario del token.
 *
 * <p>La clasificacion ya viene hecha del dispositivo; aqui solo se completa lo que se deduce
 * (slot, textura por defecto, formalidad por defecto, clima apto) y se valida.
 */
@Service
public class PrendasService {

    private static final byte[] FIRMA_PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    private static final Pattern UUID_TEXTO =
            Pattern.compile("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

    private final PrendaRepository prendas;
    private final CorreccionClasificacionRepository correcciones;
    private final AlmacenImagenes imagenes;
    private final ImagenesProperties config;
    private final Clock reloj;

    PrendasService(PrendaRepository prendas, CorreccionClasificacionRepository correcciones,
            AlmacenImagenes imagenes, ImagenesProperties config, Clock reloj) {
        this.prendas = prendas;
        this.correcciones = correcciones;
        this.imagenes = imagenes;
        this.config = config;
        this.reloj = reloj;
    }

    /**
     * Lo que manda el dispositivo de una prenda.
     *
     * @param textura {@code null} para la de por defecto del tipo
     * @param formalidad {@code null} para la de por defecto
     */
    public record NuevaPrenda(Tipo tipo, SubtipoCalzado subtipoCalzado, Patron patron, Textura textura,
            RangoFormalidad formalidad, ColorPrenda color) {}

    /** @param creada {@code false} si ya existia y se reemplazo (un reintento de la cola) */
    public record Guardado(Prenda prenda, boolean creada) {}

    /**
     * Crea la prenda, o la reemplaza si el mismo usuario ya la habia subido con ese id.
     *
     * <p>La imagen se sube antes que el documento: si Mongo falla, queda un objeto huerfano que
     * el reintento sobrescribe con la misma clave. Al reves quedaria una prenda sin imagen.
     *
     * @param id lo genera el dispositivo (UUID)
     * @throws ReglaDeNegocioException si el id no es un UUID, ya es de otro usuario, la imagen
     *     no es PNG o pasa del tope, o los atributos no son coherentes
     */
    public Guardado guardar(String usuarioId, String id, NuevaPrenda nueva, byte[] png) {
        if (id == null || !UUID_TEXTO.matcher(id).matches()) {
            throw new ReglaDeNegocioException("El id de la prenda tiene que ser un UUID");
        }
        validarImagen(png);
        Atributos atributos = ReglasPrenda.completar(nueva.tipo(), nueva.subtipoCalzado(), nueva.patron(),
                nueva.textura(), nueva.formalidad(), nueva.color());

        Optional<Prenda> existente = prendas.findById(id);
        if (existente.isPresent() && !existente.get().usuarioId().equals(usuarioId)) {
            // Un UUID repetido entre usuarios no deberia pasar nunca. No se dice de quien es.
            throw new ReglaDeNegocioException("Ese id de prenda ya esta en uso");
        }
        Instant ahora = Instant.now(reloj);
        String clave = claveImagen(usuarioId, id);
        imagenes.guardar(clave, png);
        Prenda prenda = prendas.save(new Prenda(id, usuarioId, atributos.tipo().slot(), atributos, clave,
                Prenda.VERSION_ESQUEMA, existente.map(Prenda::creadoEn).orElse(ahora), ahora));
        return new Guardado(prenda, existente.isEmpty());
    }

    public List<Prenda> listar(String usuarioId) {
        return prendas.findByUsuarioIdOrderByCreadoEnDesc(usuarioId);
    }

    /** @throws RecursoNoEncontradoException si no existe o es de otro usuario */
    public Prenda obtener(String usuarioId, String id) {
        return prendas.findById(id)
                .filter(p -> p.usuarioId().equals(usuarioId))
                .orElseThrow(() -> new RecursoNoEncontradoException("La prenda no existe"));
    }

    public String urlImagen(Prenda prenda) {
        return imagenes.urlFirmada(prenda.imagenKey());
    }

    /**
     * Lo que el usuario corrige en la pantalla de revision. Todo opcional: lo que no venga se queda.
     *
     * @param formalidad si no viene y cambia el tipo, la textura o el subtipo, se recalcula la de
     *     por defecto; si no cambia nada de eso, se conserva la que habia (quiza ya editada)
     */
    public record Correccion(Tipo tipo, SubtipoCalzado subtipoCalzado, Patron patron, Textura textura,
            RangoFormalidad formalidad, CategoriaColor categoriaColor) {}

    /**
     * Aplica la correccion y recalcula lo derivado. Si cambia la categoria de color, la registra
     * en {@code correcciones_clasificacion} para recalibrar las categorias.
     *
     * <p>Las correcciones de tipo, patron y textura no se registran todavia: falta decidir donde
     * (issue #55).
     */
    public Prenda corregir(String usuarioId, String id, Correccion correccion) {
        Prenda actual = obtener(usuarioId, id);
        Atributos antes = actual.atributos();

        Tipo tipo = correccion.tipo() != null ? correccion.tipo() : antes.tipo();
        SubtipoCalzado subtipo = correccion.subtipoCalzado() != null ? correccion.subtipoCalzado()
                : tipo == Tipo.CALZADO ? antes.subtipoCalzado() : null;
        // Al pasar de una prenda con textura a calzado o accesorio, la textura se va sola.
        Textura textura = correccion.textura() != null ? correccion.textura()
                : tipo.slot().llevaTextura() && tipo == antes.tipo() ? antes.textura() : null;
        boolean cambiaLoQueDecideLaFormalidad =
                tipo != antes.tipo() || textura != antes.textura() || subtipo != antes.subtipoCalzado();
        RangoFormalidad formalidad = correccion.formalidad() != null ? correccion.formalidad()
                : cambiaLoQueDecideLaFormalidad ? null : antes.formalidad();
        ColorPrenda color = antes.color();
        Instant ahora = Instant.now(reloj);
        if (correccion.categoriaColor() != null && correccion.categoriaColor() != color.categoria()) {
            correcciones.save(new CorreccionClasificacion(
                    UUID.randomUUID().toString(), color.lab(), correccion.categoriaColor(), ahora));
            color = color.conCategoria(correccion.categoriaColor());
        }
        Patron patron = correccion.patron() != null ? correccion.patron() : antes.patron();

        // Sin formalidad, completar pone la de por defecto (null en un accesorio neutro).
        Atributos atributos = ReglasPrenda.completar(tipo, subtipo, patron, textura, formalidad, color);
        return prendas.save(new Prenda(actual.id(), usuarioId, tipo.slot(), atributos, actual.imagenKey(),
                Prenda.VERSION_ESQUEMA, actual.creadoEn(), ahora));
    }

    /** Todo lo del usuario: imagenes y documentos. Idempotente, para poder reintentar. */
    public void borrarTodoDe(String usuarioId) {
        List<String> claves = prendas.findByUsuarioIdOrderByCreadoEnDesc(usuarioId).stream()
                .map(Prenda::imagenKey)
                .toList();
        if (!claves.isEmpty()) {
            imagenes.borrar(claves);
        }
        prendas.deleteByUsuarioId(usuarioId);
    }

    private void validarImagen(byte[] png) {
        if (png == null || png.length < FIRMA_PNG.length
                || !Arrays.equals(Arrays.copyOf(png, FIRMA_PNG.length), FIRMA_PNG)) {
            throw new ReglaDeNegocioException("La imagen de la prenda tiene que ser un PNG");
        }
        if (png.length > config.maxBytes()) {
            throw new ReglaDeNegocioException("La imagen pasa del tope de " + config.maxBytes() + " bytes");
        }
    }

    static String claveImagen(String usuarioId, String id) {
        return "usuarios/" + usuarioId + "/prendas/" + id + ".png";
    }
}
