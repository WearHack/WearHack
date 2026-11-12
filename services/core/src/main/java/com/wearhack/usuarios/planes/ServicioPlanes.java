package com.wearhack.usuarios.planes;

import com.wearhack.usuarios.CuentaEliminada;
import com.wearhack.usuarios.CuotaIaAgotadaException;
import com.wearhack.usuarios.DerechosPlan;
import com.wearhack.usuarios.PlanesUsuario;
import com.wearhack.usuarios.perfil.Usuario;
import com.wearhack.usuarios.perfil.UsuarioRepository;
import java.time.Clock;
import java.time.YearMonth;
import java.time.ZoneId;
import org.bson.Document;
import org.springframework.context.event.EventListener;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Service;

/**
 * Planes y cuota mensual de IA.
 *
 * <p>El consumo vive en {@code consumo_ia}, un documento por usuario y mes
 * ({@code _id = sub|AAAA-MM}). Un mes nuevo es un documento nuevo, asi que la cuota se
 * renueva sola, sin tarea programada. El mes se cuenta en hora de Colombia.
 */
@Service
class ServicioPlanes implements PlanesUsuario {

    static final String CONSUMO_IA = "consumo_ia";
    static final ZoneId ZONA = ZoneId.of("America/Bogota");

    private final UsuarioRepository usuarios;
    private final MongoTemplate mongo;
    private final Clock reloj;

    ServicioPlanes(UsuarioRepository usuarios, MongoTemplate mongo, Clock reloj) {
        this.usuarios = usuarios;
        this.mongo = mongo;
        this.reloj = reloj;
    }

    @Override
    public DerechosPlan derechos(String usuarioId) {
        return CatalogoPlanes.de(usuarios.findById(usuarioId).map(Usuario::planVigente).orElse(null));
    }

    @Override
    public void consumirSolicitudIa(String usuarioId) {
        DerechosPlan derechos = derechos(usuarioId);
        int limite = derechos.solicitudesIaPorMes();
        if (limite <= 0) {
            throw new CuotaIaAgotadaException(derechos.plan(), limite);
        }
        String mes = mesActual();
        // Solo coincide si queda cupo. Si el documento existe y esta lleno, el upsert intenta
        // insertar el mismo _id y Mongo lo rechaza: eso es la cuota agotada, sin carreras.
        Query conCupo = Query.query(Criteria.where("_id").is(id(usuarioId, mes)).and("solicitudes").lt(limite));
        Update sumar = new Update()
                .inc("solicitudes", 1)
                .setOnInsert("usuario_id", usuarioId)
                .setOnInsert("mes", mes);
        try {
            mongo.upsert(conCupo, sumar, CONSUMO_IA);
        } catch (DuplicateKeyException agotada) {
            throw new CuotaIaAgotadaException(derechos.plan(), limite);
        }
    }

    @Override
    public void devolverSolicitudIa(String usuarioId) {
        Query conConsumo = Query.query(
                Criteria.where("_id").is(id(usuarioId, mesActual())).and("solicitudes").gt(0));
        mongo.updateFirst(conConsumo, new Update().inc("solicitudes", -1), CONSUMO_IA);
    }

    @Override
    public int solicitudesIaUsadas(String usuarioId) {
        Document consumo = mongo.findById(id(usuarioId, mesActual()), Document.class, CONSUMO_IA);
        return consumo == null ? 0 : consumo.getInteger("solicitudes", 0);
    }

    /** El mes en curso, {@code AAAA-MM}. */
    String mesActual() {
        return YearMonth.now(reloj.withZone(ZONA)).toString();
    }

    /** Quien elimina la cuenta se lleva tambien su historial de consumo. */
    @EventListener
    void alEliminarCuenta(CuentaEliminada evento) {
        mongo.remove(Query.query(Criteria.where("usuario_id").is(evento.usuarioId())), CONSUMO_IA);
    }

    static String id(String usuarioId, String mes) {
        return usuarioId + "|" + mes;
    }
}
