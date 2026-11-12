package com.wearhack.closet.prendas;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * El bucket de las imagenes de prendas.
 *
 * @param endpoint vacio en AWS (usa el de la region); en local, el de MinIO dentro de la red
 * @param endpointPublico el que firma las URLs que recibe el telefono. En local MinIO es
 *     {@code minio:9000} para el Core pero no para el telefono; en AWS se deja vacio
 * @param accessKey vacio en AWS: las credenciales salen del rol de la tarea
 * @param maxBytes tope de la imagen decodificada
 * @param urlMinutos cuanto vale una URL firmada
 */
@ConfigurationProperties("wearhack.closet.imagenes")
public record ImagenesProperties(
        String bucket,
        String region,
        String endpoint,
        String endpointPublico,
        String accessKey,
        String secretKey,
        int maxBytes,
        int urlMinutos) {

    public ImagenesProperties {
        bucket = bucket == null || bucket.isBlank() ? "wearhack-prendas" : bucket.strip();
        region = region == null || region.isBlank() ? "us-east-1" : region.strip();
        endpoint = endpoint == null ? "" : endpoint.strip();
        endpointPublico = endpointPublico == null || endpointPublico.isBlank() ? endpoint : endpointPublico.strip();
        accessKey = accessKey == null ? "" : accessKey.strip();
        secretKey = secretKey == null ? "" : secretKey.strip();
        maxBytes = maxBytes <= 0 ? 5 * 1024 * 1024 : maxBytes;
        urlMinutos = urlMinutos <= 0 ? 15 : urlMinutos;
    }
}
