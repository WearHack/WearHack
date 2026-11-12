package com.wearhack.closet.prendas;

import java.util.Collection;

/**
 * Donde viven las imagenes sin fondo de las prendas: S3 en AWS, MinIO en local.
 *
 * <p>El bucket es privado. Al cliente se le da una URL firmada de corta duracion, nunca
 * lectura publica: una prenda es un dato personal.
 */
public interface AlmacenImagenes {

    /** Sobrescribe si la clave ya existe: reintentar una subida no deja copias. */
    void guardar(String clave, byte[] png);

    /** Las que no existan se ignoran: borrar tiene que poder reintentarse. */
    void borrar(Collection<String> claves);

    /** URL de lectura, valida unos minutos. */
    String urlFirmada(String clave);
}
