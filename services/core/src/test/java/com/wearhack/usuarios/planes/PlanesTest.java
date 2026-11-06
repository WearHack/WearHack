package com.wearhack.usuarios.planes;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.MongoDePrueba;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import com.wearhack.usuarios.CuentaEliminada;
import com.wearhack.usuarios.CuotaIaAgotadaException;
import com.wearhack.usuarios.Plan;
import com.wearhack.usuarios.colorimetria.ClienteColorimetria;
import com.wearhack.usuarios.colorimetria.Consentimiento;
import com.wearhack.usuarios.colorimetria.ConsentimientoRepository;
import com.wearhack.usuarios.colorimetria.Lab;
import com.wearhack.usuarios.colorimetria.ResultadoColorimetria;
import com.wearhack.usuarios.perfil.Usuario;
import java.time.Instant;
import java.time.YearMonth;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.stream.IntStream;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.testcontainers.junit.jupiter.Testcontainers;

/** Planes, cuota mensual de IA y su cobro en el analisis de colorimetria. */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class PlanesTest {

    private static final String SUB = "sub-planes-test";
    private static final Instant AHORA = Instant.parse("2026-11-01T12:00:00Z");
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3};
    private static final String ANALISIS = "/api/v1/usuarios/me/colorimetria";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MongoTemplate mongo;

    @Autowired
    private ServicioPlanes planes;

    @Autowired
    private ConsentimientoRepository consentimientos;

    @Autowired
    private ApplicationEventPublisher eventos;

    @MockitoBean
    private ClienteColorimetria ia;

    @BeforeEach
    void limpiar() {
        mongo.getDb().drop();
    }

    @Test
    void sinTokenResponde401() throws Exception {
        mockMvc.perform(get("/api/v1/usuarios/me/plan")).andExpect(status().isUnauthorized());
    }

    @Test
    void sinPerfilElPlanEsGratis() throws Exception {
        mockMvc.perform(get("/api/v1/usuarios/me/plan").with(usuario()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan").value("GRATIS"))
                .andExpect(jsonPath("$.derechos.solicitudesIaPorMes").value(15))
                .andExpect(jsonPath("$.derechos.maxPrendas").value(CatalogoPlanes.PRENDAS_PLAN_GRATIS))
                .andExpect(jsonPath("$.derechos.dressCodesPorMes").value(CatalogoPlanes.DRESS_CODES_PLAN_GRATIS))
                .andExpect(jsonPath("$.derechos.escaneoEnTienda").value(false))
                .andExpect(jsonPath("$.solicitudesIaUsadas").value(0))
                .andExpect(jsonPath("$.solicitudesIaRestantes").value(15));
    }

    @Test
    void plusTieneTodoIlimitadoYSusFunciones() throws Exception {
        mongo.save(new Usuario(SUB, "Ana", AHORA, AHORA, AHORA, Plan.PLUS));

        mockMvc.perform(get("/api/v1/usuarios/me/plan").with(usuario()))
                .andExpect(jsonPath("$.plan").value("PLUS"))
                .andExpect(jsonPath("$.derechos.solicitudesIaPorMes").value(30))
                .andExpect(jsonPath("$.derechos.maxPrendas").isEmpty())
                .andExpect(jsonPath("$.derechos.escaneoEnTienda").value(true))
                .andExpect(jsonPath("$.derechos.analisisDelCloset").value(true))
                .andExpect(jsonPath("$.derechos.maleta").value(true));
        mockMvc.perform(get("/api/v1/usuarios/me").with(usuario())).andExpect(jsonPath("$.plan").value("PLUS"));
    }

    @Test
    void unPerfilAnteriorALosPlanesEsGratis() throws Exception {
        mongo.getCollection("usuarios").insertOne(new Document("_id", SUB)
                .append("mayoria_edad_declarada_en", java.util.Date.from(AHORA))
                .append("creado_en", java.util.Date.from(AHORA))
                .append("actualizado_en", java.util.Date.from(AHORA)));

        mockMvc.perform(get("/api/v1/usuarios/me").with(usuario())).andExpect(jsonPath("$.plan").value("GRATIS"));
        assertThat(planes.derechos(SUB).plan()).isEqualTo(Plan.GRATIS);
    }

    @Test
    void elRegistroNuevoEmpiezaEnGratis() throws Exception {
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put("/api/v1/usuarios/me")
                        .with(usuario())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"mayorDeEdad\":true}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.plan").value("GRATIS"));
        assertThat(mongo.getCollection("usuarios").find(new Document("_id", SUB)).first().getString("plan"))
                .isEqualTo("GRATIS");
    }

    @Test
    void laCuotaSeAgotaEnElTopeDelPlan() {
        for (int i = 0; i < 15; i++) {
            planes.consumirSolicitudIa(SUB);
        }

        assertThatThrownBy(() -> planes.consumirSolicitudIa(SUB)).isInstanceOf(CuotaIaAgotadaException.class);
        assertThat(planes.solicitudesIaUsadas(SUB)).isEqualTo(15);
    }

    @Test
    void elPlanDePagoTieneMasCuota() {
        mongo.save(new Usuario(SUB, null, AHORA, AHORA, AHORA, Plan.ESENCIAL));
        for (int i = 0; i < 30; i++) {
            planes.consumirSolicitudIa(SUB);
        }

        assertThatThrownBy(() -> planes.consumirSolicitudIa(SUB)).isInstanceOf(CuotaIaAgotadaException.class);
    }

    @Test
    void peticionesSimultaneasNoPasanDelTope() throws Exception {
        ExecutorService hilos = Executors.newFixedThreadPool(8);
        try {
            List<Callable<Boolean>> intentos = IntStream.range(0, 40).<Callable<Boolean>>mapToObj(i -> () -> {
                try {
                    planes.consumirSolicitudIa(SUB);
                    return true;
                } catch (CuotaIaAgotadaException agotada) {
                    return false;
                }
            }).toList();

            long aceptadas = 0;
            for (Future<Boolean> intento : hilos.invokeAll(intentos)) {
                if (intento.get()) {
                    aceptadas++;
                }
            }
            assertThat(aceptadas).isEqualTo(15);
            assertThat(planes.solicitudesIaUsadas(SUB)).isEqualTo(15);
        } finally {
            hilos.shutdownNow();
        }
    }

    @Test
    void elConsumoDelMesAnteriorNoCuenta() {
        String mesAnterior = YearMonth.parse(planes.mesActual()).minusMonths(1).toString();
        mongo.getCollection(ServicioPlanes.CONSUMO_IA).insertOne(
                new Document("_id", ServicioPlanes.id(SUB, mesAnterior))
                        .append("usuario_id", SUB)
                        .append("mes", mesAnterior)
                        .append("solicitudes", 15));

        planes.consumirSolicitudIa(SUB);

        assertThat(planes.solicitudesIaUsadas(SUB)).isEqualTo(1);
    }

    @Test
    void devolverNoBajaDeCero() {
        planes.consumirSolicitudIa(SUB);
        planes.devolverSolicitudIa(SUB);
        planes.devolverSolicitudIa(SUB);

        assertThat(planes.solicitudesIaUsadas(SUB)).isZero();
    }

    @Test
    void eliminarLaCuentaBorraSuConsumo() {
        planes.consumirSolicitudIa(SUB);
        planes.consumirSolicitudIa("otro-sub");

        eventos.publishEvent(new CuentaEliminada(SUB));

        assertThat(mongo.getCollection(ServicioPlanes.CONSUMO_IA).countDocuments(new Document("usuario_id", SUB)))
                .isZero();
        assertThat(planes.solicitudesIaUsadas("otro-sub")).isEqualTo(1);
    }

    @Test
    void unAnalisisExitosoGastaUnaSolicitud() throws Exception {
        otorgarConsentimiento();
        when(ia.analizar(any(byte[].class))).thenReturn(new ResultadoColorimetria(
                "otono", 0.8, List.of("piel"), new Lab(62, 14, 19), null, null));

        analizar().andExpect(status().isOk());

        assertThat(planes.solicitudesIaUsadas(SUB)).isEqualTo(1);
    }

    @Test
    void unAnalisisFallidoNoGastaCuota() throws Exception {
        otorgarConsentimiento();
        when(ia.analizar(any(byte[].class))).thenThrow(new ServicioIaNoDisponibleException("caida", null));

        analizar().andExpect(status().isServiceUnavailable());

        assertThat(planes.solicitudesIaUsadas(SUB)).isZero();
    }

    @Test
    void sinConsentimientoNoGastaCuota() throws Exception {
        analizar().andExpect(status().isUnprocessableContent());

        assertThat(planes.solicitudesIaUsadas(SUB)).isZero();
    }

    @Test
    void conLaCuotaAgotadaResponde429SinLlamarALaIa() throws Exception {
        otorgarConsentimiento();
        for (int i = 0; i < 15; i++) {
            planes.consumirSolicitudIa(SUB);
        }

        analizar()
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.mensaje").value(org.hamcrest.Matchers.containsString("15 solicitudes")));

        verify(ia, never()).analizar(any(byte[].class));
        assertThat(planes.solicitudesIaUsadas(SUB)).isEqualTo(15);
    }

    @Test
    void consultarElPerfilDeColorimetriaNoGastaCuota() throws Exception {
        mockMvc.perform(get(ANALISIS).with(usuario()));

        assertThat(planes.solicitudesIaUsadas(SUB)).isZero();
    }

    private ResultActions analizar() throws Exception {
        return mockMvc.perform(post(ANALISIS).with(usuario()).contentType(MediaType.IMAGE_PNG).content(PNG));
    }

    private void otorgarConsentimiento() {
        consentimientos.save(new Consentimiento(
                "consentimiento-planes", SUB, "colorimetria", "v1", Consentimiento.OTORGADO, AHORA, null));
    }

    private static RequestPostProcessor usuario() {
        return jwt().jwt(token -> token.subject(SUB));
    }
}
