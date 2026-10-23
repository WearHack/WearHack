package com.wearhack.plataforma;

/**
 * Lo pedido no existe para quien lo pide. Se responde con 404.
 *
 * <p>Tambien se usa cuando el recurso existe pero es de otro usuario: decir 403 confirmaria
 * que existe, y eso ya es informacion sobre otra persona.
 */
public class RecursoNoEncontradoException extends RuntimeException {

    public RecursoNoEncontradoException(String mensaje) {
        super(mensaje);
    }
}
