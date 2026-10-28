package com.wearhack.plataforma;

/** El servicio de IA no respondio a tiempo o respondio algo inutilizable. Se responde con 503. */
public class ServicioIaNoDisponibleException extends RuntimeException {

    public ServicioIaNoDisponibleException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}