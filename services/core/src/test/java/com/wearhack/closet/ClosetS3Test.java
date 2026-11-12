package com.wearhack.closet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import com.wearhack.MongoDePrueba;
import com.wearhack.closet.prendas.PrendaRepository;
import com.wearhack.usuarios.CuentaEliminada;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Base64;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.wait.strategy.Wait;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

/**
 * El camino completo de la imagen contra un S3 local (issue #25): sube con el PUT, se descarga
 * con la URL firmada del GET sin credenciales, y desaparece al eliminar la cuenta.
 *
 * <p>El S3 es Adobe S3Mock: MinIO dejo de publicar imagenes (quay.io responde 401 y Docker Hub ya
 * no las tiene). S3Mock no valida firmas, asi que aqui se comprueba que la URL viene firmada; que
 * el bucket rechace una URL sin firma lo garantiza S3 en AWS.
 *
 * <p>Lo unico simulado es el token: en local no hay User Pool de Cognito.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(MongoDePrueba.class)
@Testcontainers(disabledWithoutDocker = true)
class ClosetS3Test {

    private static final String SUB = "sub-closet-s3";
    private static final String ID = "9c8b7a6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d";
    private static final String BUCKET = "wearhack-prendas-test";
    private static final String USUARIO = "s3-prueba";
    private static final String CLAVE = "s3-prueba-secreta";
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 42, 7, 13};

    /** La misma imagen que el compose, para no bajar otra. */
    private static final GenericContainer<?> S3 = new GenericContainer<>(
            DockerImageName.parse("adobe/s3mock:5.2.3"))
            .withExposedPorts(9090)
            .waitingFor(Wait.forHttp("/").forPort(9090));

    private static S3Client s3;

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private PrendaRepository prendas;

    @Autowired
    private ApplicationEventPublisher eventos;

    @DynamicPropertySource
    static void s3(DynamicPropertyRegistry propiedades) {
        S3.start();
        propiedades.add("wearhack.closet.imagenes.endpoint", ClosetS3Test::urlS3);
        propiedades.add("wearhack.closet.imagenes.endpoint-publico", ClosetS3Test::urlS3);
        propiedades.add("wearhack.closet.imagenes.bucket", () -> BUCKET);
        propiedades.add("wearhack.closet.imagenes.access-key", () -> USUARIO);
        propiedades.add("wearhack.closet.imagenes.secret-key", () -> CLAVE);
    }

    @BeforeAll
    static void crearBucket() {
        // Corre antes que el contexto de Spring; start() no hace nada si ya esta arriba.
        S3.start();
        s3 = S3Client.builder()
                .endpointOverride(URI.create(urlS3()))
                .region(Region.US_EAST_1)
                .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(USUARIO, CLAVE)))
                .forcePathStyle(true)
                .build();
        s3.createBucket(b -> b.bucket(BUCKET));
    }

    @AfterAll
    static void cerrar() {
        s3.close();
        S3.stop();
    }

    private static String urlS3() {
        return "http://" + S3.getHost() + ":" + S3.getMappedPort(9090);
    }

    @Test
    void laImagenSubeSeDescargaConLaUrlFirmadaYSeBorraConLaCuenta() throws Exception {
        prendas.deleteAll();
        String clave = "usuarios/" + SUB + "/prendas/" + ID + ".png";

        mockMvc.perform(put("/api/v1/closet/me/prendas/" + ID).with(jwt().jwt(t -> t.subject(SUB)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"tipo":"CAMISETA","patron":"LISO",
                                 "color":{"lab":[90,0,2],"categoria":"BLANCO"},"imagenPng":"%s"}
                                """.formatted(Base64.getEncoder().encodeToString(PNG))))
                .andExpect(status().isCreated());

        // En el bucket, con el tipo de contenido correcto.
        var objeto = s3.getObjectAsBytes(g -> g.bucket(BUCKET).key(clave));
        assertThat(objeto.asByteArray()).isEqualTo(PNG);
        assertThat(objeto.response().contentType()).isEqualTo("image/png");

        // La URL firmada del closet se abre sin credenciales, como la abriria el telefono.
        String cuerpo = mockMvc.perform(get("/api/v1/closet/me/prendas").with(jwt().jwt(t -> t.subject(SUB))))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        String url = JsonPath.read(cuerpo, "$.prendas[0].imagenUrl");
        try (HttpClient http = HttpClient.newHttpClient()) {
            HttpResponse<byte[]> descarga = http.send(
                    HttpRequest.newBuilder(URI.create(url)).GET().build(), HttpResponse.BodyHandlers.ofByteArray());
            assertThat(descarga.statusCode()).isEqualTo(200);
            assertThat(descarga.body()).isEqualTo(PNG);

            // Es una URL firmada y de corta duracion, no un enlace publico.
            assertThat(url).contains("X-Amz-Signature=", "X-Amz-Expires=");
        }

        eventos.publishEvent(new CuentaEliminada(SUB));

        assertThat(prendas.count()).isZero();
        assertThatThrownBy(() -> s3.getObjectAsBytes(g -> g.bucket(BUCKET).key(clave)))
                .isInstanceOf(NoSuchKeyException.class);
    }
}
