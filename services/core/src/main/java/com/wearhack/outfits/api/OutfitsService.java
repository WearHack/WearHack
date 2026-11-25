package com.wearhack.outfits.api;

import com.wearhack.closet.PrendasParaOutfits;
import com.wearhack.closet.PrendasParaOutfits.Prenda;
import com.wearhack.closet.PrendasParaOutfits.Rango;
import com.wearhack.outfits.api.LoteOutfits.Opcion;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.usuarios.CuentaEliminada;
import com.wearhack.usuarios.PlanesUsuario;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.function.UnaryOperator;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import org.bson.Document;
import org.springframework.context.event.EventListener;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
class OutfitsService {
    private static final ZoneId COLOMBIA = ZoneId.of("America/Bogota");
    private static final List<String> NIVELES = List.of("DEPORTIVO", "CASUAL", "SMART_CASUAL", "FORMAL");
    private static final String CALZADO = "CALZADO";

    private final PrendasParaOutfits closet;
    private final ClienteRecomendador motor;
    private final LotesOutfitsRepository lotes;
    private final DiasOutfitsRepository dias;
    private final PlanesUsuario planes;
    private final MongoTemplate mongo;
    private final Clock reloj;

    OutfitsService(PrendasParaOutfits closet, ClienteRecomendador motor, LotesOutfitsRepository lotes,
            DiasOutfitsRepository dias, PlanesUsuario planes, MongoTemplate mongo, Clock reloj) {
        this.closet = closet;
        this.motor = motor;
        this.lotes = lotes;
        this.dias = dias;
        this.planes = planes;
        this.mongo = mongo;
        this.reloj = reloj;
    }

    enum Ocasion {
        DEPORTE("DEPORTIVO", "DEPORTIVO"),
        DIA_A_DIA("DEPORTIVO", "SMART_CASUAL"),
        SALIDA_CASUAL("CASUAL", "SMART_CASUAL"),
        OFICINA("SMART_CASUAL", "FORMAL"),
        ENTREVISTA("SMART_CASUAL", "FORMAL"),
        CENA_ELEGANTE("SMART_CASUAL", "FORMAL"),
        FORMAL("FORMAL", "FORMAL");

        final Rango inicial;

        Ocasion(String min, String max) {
            inicial = new Rango(min, max);
        }
    }

    enum Mood { RELAJADO, ELEGANTE, ATREVIDO, DISCRETO }
    enum Clima { FRIO, TEMPLADO, CALIDO }

    record Contexto(Ocasion ocasion, Mood mood, Clima clima) {}
    record Hoy(String id, String fecha, List<Opcion> opciones, String elegidoId, Opcion elegido) {}
    record Dia(String fecha, Opcion outfit) {}

    Hoy opcionesHoy(String usuario, Contexto contexto) {
        LocalDate hoy = hoy();
        List<Prenda> prendas = closet.listar(usuario);
        DiaOutfit dia = leerDia(usuario, hoy);
        if (dia.outfitElegido() != null) {
            Map<String, Prenda> actuales = porId(prendas);
            Opcion elegido = lotes.findById(dia.loteElegido()).filter(l -> l.usuario().equals(usuario))
                    .stream().flatMap(l -> l.opciones().stream())
                    .filter(o -> o.id().equals(dia.outfitElegido()) && vigente(o, actuales))
                    .findFirst().orElse(null);
            return new Hoy(dia.loteElegido(), hoy.toString(), List.of(), dia.outfitElegido(), elegido);
        }
        LoteOutfits lote = generar(usuario, hoy, contexto, prendas);
        return new Hoy(lote.id(), lote.fecha(), lote.opciones(), null, null);
    }

    List<Opcion> opcionesSemana(String usuario) {
        LocalDate hoy = hoy();
        List<Prenda> prendas = closet.listar(usuario);
        Map<String, Opcion> catalogo = catalogo(usuario, lunes(hoy), porId(prendas));
        if (catalogo.isEmpty()) {
            return generar(usuario, hoy, new Contexto(Ocasion.DIA_A_DIA, null, null), prendas).opciones();
        }
        var combinaciones = new HashSet<List<String>>();
        return catalogo.values().stream().filter(o -> combinaciones.add(o.prendas().stream().sorted().toList()))
                .toList();
    }

    List<Dia> plan(String usuario) {
        LocalDate lunes = lunes(hoy());
        Map<String, Opcion> catalogo = catalogo(usuario, lunes, porId(closet.listar(usuario)));
        List<LocalDate> fechas = IntStream.range(0, 7).mapToObj(lunes::plusDays).toList();
        List<String> ids = fechas.stream().map(fecha -> DiaOutfit.vacio(usuario, fecha.toString()).id()).toList();
        Map<String, DiaOutfit> guardados = dias.findAllById(ids).stream()
                .collect(Collectors.toMap(DiaOutfit::fecha, dia -> dia));
        return fechas.stream().map(fecha -> {
            DiaOutfit dia = guardados.get(fecha.toString());
            String asignado = dia == null ? null : dia.asignado();
            return new Dia(fecha.toString(), asignado == null ? null : catalogo.get(asignado));
        }).toList();
    }

    void asignar(String usuario, LocalDate fecha, String outfitId) {
        LocalDate lunes = lunes(hoy());
        if (fecha.isBefore(lunes) || fecha.isAfter(lunes.plusDays(6))) {
            throw new ReglaDeNegocioException("El día debe pertenecer a la semana en curso");
        }
        if (outfitId != null && !catalogo(usuario, lunes, porId(closet.listar(usuario))).containsKey(outfitId)) {
            throw new ReglaDeNegocioException("El outfit no está disponible en tu clóset");
        }
        guardarDia(usuario, fecha, dia -> dia.conAsignacion(outfitId));
    }

    void elegir(String usuario, String loteId, String outfitId) {
        LocalDate hoy = hoy();
        LoteOutfits lote = lotes.findById(loteId)
                .filter(l -> usuario.equals(l.usuario()) && hoy.toString().equals(l.fecha()))
                .orElseThrow(() -> new ReglaDeNegocioException("El lote ya no está disponible"));
        Map<String, Prenda> actuales = porId(closet.listar(usuario));
        if (lote.opciones().stream().noneMatch(o -> outfitId.equals(o.id()) && vigente(o, actuales))) {
            throw new ReglaDeNegocioException("El outfit ya no está disponible en tu clóset");
        }
        guardarDia(usuario, hoy, dia -> {
            if (outfitId.equals(dia.outfitElegido()) && loteId.equals(dia.loteElegido())) return dia;
            if (dia.outfitElegido() != null) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "Ya elegiste un outfit para hoy");
            }
            return dia.conEleccion(loteId, outfitId);
        });
    }

    private void guardarDia(String usuario, LocalDate fecha, UnaryOperator<DiaOutfit> cambiar) {
        for (int intento = 0; intento < 4; intento++) {
            DiaOutfit actual = leerDia(usuario, fecha);
            DiaOutfit nuevo = cambiar.apply(actual);
            if (actual == nuevo || Objects.equals(actual, nuevo)) return;
            try {
                dias.save(nuevo);
                return;
            } catch (DuplicateKeyException | OptimisticLockingFailureException colision) {
                // Se vuelve a leer para conservar una elección o asignación concurrente.
            }
        }
        throw new ResponseStatusException(HttpStatus.CONFLICT, "El plan cambió. Inténtalo de nuevo");
    }

    private LoteOutfits generar(String usuario, LocalDate fecha, Contexto contexto, List<Prenda> prendas) {
        List<Prenda> candidatas = prendas.stream().limit(1000).toList();
        Rango rango = rango(contexto.ocasion());
        String huella = candidatas.stream().sorted(Comparator.comparing(Prenda::id))
                .map(p -> p.id() + ":" + p.actualizada()).collect(Collectors.joining(","));
        String id = idDe(usuario + "/" + fecha + "/" + contexto + "/" + rango + "/" + huella);
        var guardado = lotes.findById(id);
        if (guardado.isPresent()) return guardado.get();
        var nuevo = new LoteOutfits(id, usuario, fecha.toString(), List.of());
        if (puedeCombinar(candidatas)) {
            Map<String, Prenda> porId = porId(candidatas);
            String clima = contexto.clima() == null ? null : contexto.clima().name();
            String mood = contexto.mood() == null ? null : contexto.mood().name();
            planes.consumirSolicitudIa(usuario);
            try {
                var combinaciones = motor.generar(usuario, contexto.ocasion().name(), mood, clima, rango, candidatas);
                nuevo = new LoteOutfits(id, usuario, fecha.toString(), combinaciones.stream()
                        .filter(c -> c.prendas() != null && !c.prendas().isEmpty()
                                && porId.keySet().containsAll(c.prendas()))
                        .map(c -> new Opcion(idDe(id + "/" + c.prendas()), c.prendas(),
                                formalidad(c.prendas(), porId, rango), clima, c.costo()))
                        .toList());
                return lotes.insert(nuevo);
            } catch (DuplicateKeyException colision) {
                planes.devolverSolicitudIa(usuario);
                return lotes.findById(id).orElseThrow(() -> colision);
            } catch (RuntimeException fallo) {
                planes.devolverSolicitudIa(usuario);
                throw fallo;
            }
        }
        try {
            return lotes.insert(nuevo);
        } catch (DuplicateKeyException colision) {
            return lotes.findById(id).orElseThrow(() -> colision);
        }
    }

    private Rango rango(Ocasion ocasion) {
        Document configuracion = mongo.findById("outfits", Document.class, "configuracion");
        Document codigos = configuracion == null ? null : configuracion.get("dress_codes", Document.class);
        Document codigo = codigos == null ? null : codigos.get(ocasion.name(), Document.class);
        if (codigo != null) {
            String min = codigo.getString("min");
            String max = codigo.getString("max");
            if (min != null && max != null && NIVELES.indexOf(min) >= 0
                    && NIVELES.indexOf(max) >= NIVELES.indexOf(min)) {
                return new Rango(min, max);
            }
        }
        return ocasion.inicial;
    }

    private static boolean puedeCombinar(List<Prenda> prendas) {
        var slots = prendas.stream().map(Prenda::slot).collect(Collectors.toSet());
        return slots.contains(CALZADO) && (slots.contains("CUERPO_COMPLETO")
                || slots.containsAll(List.of("TORSO_SUPERIOR", "TORSO_INFERIOR")));
    }

    private static String formalidad(List<String> seleccion, Map<String, Prenda> prendas, Rango evento) {
        int suelo = seleccion.stream().map(prendas::get).map(Prenda::formalidad).filter(Objects::nonNull)
                .mapToInt(rango -> NIVELES.indexOf(rango.min())).max().orElse(0);
        return NIVELES.get(Math.max(suelo, NIVELES.indexOf(evento.min())));
    }

    private Map<String, Opcion> catalogo(String usuario, LocalDate lunes, Map<String, Prenda> prendas) {
        Map<String, Opcion> catalogo = new LinkedHashMap<>();
        lotes.findByUsuarioAndFechaBetweenOrderByFechaDesc(
                usuario, lunes.minusDays(1).toString(), lunes.plusDays(7).toString()).stream()
                .flatMap(l -> l.opciones().stream()).filter(o -> vigente(o, prendas))
                .forEach(o -> catalogo.put(o.id(), o));
        return catalogo;
    }

    private static boolean vigente(Opcion opcion, Map<String, Prenda> prendas) {
        return prendas.keySet().containsAll(opcion.prendas());
    }

    private static Map<String, Prenda> porId(List<Prenda> prendas) {
        return prendas.stream().collect(Collectors.toMap(Prenda::id, p -> p));
    }

    private DiaOutfit leerDia(String usuario, LocalDate fecha) {
        DiaOutfit vacio = DiaOutfit.vacio(usuario, fecha.toString());
        return dias.findById(vacio.id()).orElse(vacio);
    }

    private LocalDate hoy() {
        return LocalDate.now(reloj.withZone(COLOMBIA));
    }

    private static LocalDate lunes(LocalDate fecha) {
        return fecha.minusDays(fecha.getDayOfWeek().getValue() - 1L);
    }

    private static String idDe(String contenido) {
        return UUID.nameUUIDFromBytes(contenido.getBytes(StandardCharsets.UTF_8)).toString();
    }

    @EventListener
    void alEliminarCuenta(CuentaEliminada evento) {
        dias.deleteByUsuario(evento.usuarioId());
        lotes.deleteByUsuario(evento.usuarioId());
    }
}
