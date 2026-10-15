package com.wearhack.plataforma;

/** El proveedor de identidad fallo. Se responde con 502: el error no es del cliente. */
public class ProveedorIdentidadException extends RuntimeException {

    public ProveedorIdentidadException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}
