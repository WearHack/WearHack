package com.wearhack.plataforma;

/**
 * Operaciones sobre las cuentas del proveedor de identidad (Cognito).
 *
 * <p>El Core no gestiona credenciales: el registro y el login van directo del cliente a
 * Cognito. Lo unico que el Core le pide es borrar una cuenta, cuando el usuario elimina
 * la suya.
 */
public interface ProveedorIdentidad {

    /**
     * Elimina la cuenta. Si ya no existe, no es un error: el borrado tiene que poder
     * reintentarse.
     *
     * @param nombreUsuario el claim {@code username} del token de acceso. En una cuenta
     *     federada (Google) no coincide con el {@code sub}, por eso no se usa el {@code sub}.
     * @throws ProveedorIdentidadException si el proveedor no responde o rechaza la operacion
     */
    void eliminarCuenta(String nombreUsuario);
}
