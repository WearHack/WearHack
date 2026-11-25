package com.wearhack.closet.prendas;

import java.net.URI;
import java.time.Duration;
import java.util.Collection;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.Delete;
import software.amazon.awssdk.services.s3.model.ObjectIdentifier;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

/**
 * S3 con el SDK de AWS. Contra MinIO hace falta el estilo de ruta ({@code host/bucket/clave}):
 * MinIO no resuelve buckets como subdominios.
 */
@Component
@EnableConfigurationProperties(ImagenesProperties.class)
class S3AlmacenImagenes implements AlmacenImagenes {

    /** El limite de DeleteObjects. */
    private static final int MAXIMO_POR_BORRADO = 1000;

    private final S3Client s3;
    private final S3Presigner firmador;
    private final String bucket;
    private final Duration vigenciaUrl;

    S3AlmacenImagenes(ImagenesProperties config) {
        Region region = Region.of(config.region());
        AwsCredentialsProvider credenciales = config.accessKey().isEmpty()
                ? DefaultCredentialsProvider.builder().build()
                : StaticCredentialsProvider.create(AwsBasicCredentials.create(config.accessKey(), config.secretKey()));
        S3Configuration rutas = S3Configuration.builder().pathStyleAccessEnabled(true).build();

        var clientes = S3Client.builder().region(region).credentialsProvider(credenciales).serviceConfiguration(rutas);
        if (!config.endpoint().isEmpty()) {
            clientes.endpointOverride(URI.create(config.endpoint()));
        }
        var firmadores = S3Presigner.builder().region(region).credentialsProvider(credenciales)
                .serviceConfiguration(rutas);
        if (!config.endpointPublico().isEmpty()) {
            firmadores.endpointOverride(URI.create(config.endpointPublico()));
        }
        this.s3 = clientes.build();
        this.firmador = firmadores.build();
        this.bucket = config.bucket();
        this.vigenciaUrl = Duration.ofMinutes(config.urlMinutos());
    }

    @Override
    public void guardar(String clave, byte[] png) {
        s3.putObject(p -> p.bucket(bucket).key(clave).contentType("image/png"), RequestBody.fromBytes(png));
    }

    @Override
    public void borrar(Collection<String> claves) {
        var lista = claves.stream().map(c -> ObjectIdentifier.builder().key(c).build()).toList();
        for (int i = 0; i < lista.size(); i += MAXIMO_POR_BORRADO) {
            var lote = lista.subList(i, Math.min(i + MAXIMO_POR_BORRADO, lista.size()));
            var respuesta =
                    s3.deleteObjects(d -> d.bucket(bucket).delete(Delete.builder().objects(lote).quiet(true).build()));
            if (!respuesta.errors().isEmpty()) {
                throw new IllegalStateException("El almacen no pudo borrar " + respuesta.errors().size() + " imagenes");
            }
        }
    }

    @Override
    public String urlFirmada(String clave) {
        return firmador.presignGetObject(p -> p.signatureDuration(vigenciaUrl)
                        .getObjectRequest(g -> g.bucket(bucket).key(clave)))
                .url()
                .toString();
    }
}
