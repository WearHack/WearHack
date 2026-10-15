package com.wearhack.plataforma;

import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;

/**
 * Cuerpo de toda respuesta de error del Core, venga de un controlador o de la capa de
 * seguridad. Una sola forma para que el cliente tenga un solo parser.
 */
public record ErrorApi(Instant momento, int estado, String error, String mensaje, String ruta) {

    public static ErrorApi de(HttpStatusCode estado, String mensaje, String ruta) {
        HttpStatus conocido = HttpStatus.resolve(estado.value());
        String error = conocido != null ? conocido.getReasonPhrase() : "Error";
        return new ErrorApi(Instant.now(), estado.value(), error, mensaje, ruta);
    }
}
