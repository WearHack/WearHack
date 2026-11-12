package com.wearhack.closet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.wearhack.MongoDePrueba;
import com.wearhack.closet.prendas.AlmacenImagenes;
import com.wearhack.closet.prendas.CorreccionClasificacion;
import com.wearhack.closet.prendas.CorreccionClasificacionRepository;
import com.wearhack.closet.prendas.Prenda;
import com.wearhack.closet.prendas.PrendaRepository;
import com.wearhack.usuarios.CuentaEliminada;
import java.util.Base64;
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
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Los endpoints del closet contra un Mongo real (issue #25). S3 se reemplaza por un mock: lo que
 * se prueba aqui es el contrato con el cliente y lo que queda en Mongo, con los nombres de campo
 * del esquema de {@code infra/datos}.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class ClosetPrendasTest {

    private static final String SUB = "sub-closet-test";
    private static final String ID = "6a1d2c3b-4e5f-4a7b-8c9d-0e1f2a3b4c5d";
    private static final String RUTA = "/api/v1/closet/me/prendas";
    private static final String PNG = Base64.getEncoder().encodeToString(
            new byte[] {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3});

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MongoTemplate mongo;

    @Autowired
    private PrendaRepository prendas;

    @Autowired
    private CorreccionClasificacionRepository correcciones;

    @Autowired
    private ApplicationEventPublisher eventos;

    @MockitoBean
    private AlmacenImagenes imagenes;

    @BeforeEach
    void preparar() {
        prendas.deleteAll();
        correcciones.deleteAll();
        when(imagenes.urlFirmada(anyString())).thenAnswer(i -> "https://firmada/" + i.getArgument(0));
    }

    @Test
    void sinTokenResponde401() throws Exception {
        mockMvc.perform(get(RUTA)).andExpect(status().isUnauthorized());
    }

    @Test
    void guardarCreaConLoDeducidoYUnReintentoNoDuplica() throws Exception {
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(pantalon()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(ID))
                .andExpect(jsonPath("$.slotOutfit").value("TORSO_INFERIOR"))
                .andExpect(jsonPath("$.textura").value("DENIM"))
                .andExpect(jsonPath("$.formalidad.min").value("CASUAL"))
                .andExpect(jsonPath("$.climaApto[0]").value("FRIO"))
                .andExpect(jsonPath("$.color.categoria").value("AZUL"))
                .andExpect(jsonPath("$.imagenUrl").value("https://firmada/usuarios/" + SUB + "/prendas/" + ID + ".png"));

        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(pantalon()))
                .andExpect(status().isOk());

        assertThat(prendas.count()).isEqualTo(1);
    }

    @Test
    void enMongoQuedanLosNombresDelEsquema() throws Exception {
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(pantalon()))
                .andExpect(status().isCreated());

        Document crudo = mongo.getCollection(Prenda.COLECCION).find().first();
        assertThat(crudo.getString("usuario_id")).isEqualTo(SUB);
        assertThat(crudo.getString("slot_outfit")).isEqualTo("TORSO_INFERIOR");
        assertThat(crudo.getString("imagen_key")).isEqualTo("usuarios/" + SUB + "/prendas/" + ID + ".png");
        assertThat(crudo.getInteger("version_esquema")).isEqualTo(1);
        assertThat(crudo.get("creado_en")).isInstanceOf(java.util.Date.class);
        Document atributos = crudo.get("atributos", Document.class);
        assertThat(atributos.getString("tipo")).isEqualTo("PANTALON");
        assertThat(atributos.getList("clima_apto", String.class)).containsExactly("FRIO", "TEMPLADO");
        assertThat(atributos.get("formalidad", Document.class).getString("min")).isEqualTo("CASUAL");
        assertThat(atributos.get("color", Document.class).getList("lab", Double.class)).containsExactly(40.0, 5.0, -40.0);
        assertThat(atributos.get("color", Document.class).getString("categoria")).isEqualTo("AZUL");
    }

    @Test
    void atributosIncoherentesResponden422() throws Exception {
        String bolsoConTextura = """
                {"tipo":"BOLSO","patron":"LISO","textura":"CUERO",
                 "color":{"lab":[30,10,20],"categoria":"CAFE"},"imagenPng":"%s"}
                """.formatted(PNG);
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(bolsoConTextura))
                .andExpect(status().isUnprocessableContent());
    }

    @Test
    void unTipoDesconocidoResponde400() throws Exception {
        String desconocido = pantalon().replace("\"PANTALON\"", "\"JEAN\"");
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(desconocido))
                .andExpect(status().isBadRequest());
    }

    @Test
    void cadaUnoVeSoloSuCloset() throws Exception {
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario("otro-sub"))
                        .contentType(MediaType.APPLICATION_JSON).content(pantalon()))
                .andExpect(status().isCreated());

        mockMvc.perform(get(RUTA).with(usuario(SUB)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.prendas.length()").value(0));
        mockMvc.perform(get(RUTA + "/" + ID).with(usuario(SUB)))
                .andExpect(status().isNotFound());
        mockMvc.perform(get(RUTA).with(usuario("otro-sub")))
                .andExpect(jsonPath("$.prendas.length()").value(1));
    }

    @Test
    void corregirLaCategoriaQuedaEnCorreccionesSinUsuario() throws Exception {
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(pantalon()))
                .andExpect(status().isCreated());

        mockMvc.perform(patch(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"categoriaColor\":\"AZUL_MARINO\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.color.categoria").value("AZUL_MARINO"));

        Document crudo = mongo.getCollection(CorreccionClasificacion.COLECCION).find().first();
        assertThat(crudo.getString("categoria_confirmada")).isEqualTo("AZUL_MARINO");
        assertThat(crudo.getList("lab", Double.class)).containsExactly(40.0, 5.0, -40.0);
        assertThat(crudo.containsKey("usuario_id")).isFalse();
    }

    @Test
    void alEliminarLaCuentaSeBorranSusPrendas() throws Exception {
        mockMvc.perform(put(RUTA + "/" + ID).with(usuario(SUB))
                        .contentType(MediaType.APPLICATION_JSON).content(pantalon()))
                .andExpect(status().isCreated());

        eventos.publishEvent(new CuentaEliminada(SUB));

        assertThat(prendas.count()).isZero();
    }

    private static String pantalon() {
        return """
                {"tipo":"PANTALON","patron":"LISO",
                 "color":{"lab":[40,5,-40],"categoria":"AZUL"},"imagenPng":"%s"}
                """.formatted(PNG);
    }

    private static RequestPostProcessor usuario(String sub) {
        return jwt().jwt(token -> token.subject(sub));
    }
}
