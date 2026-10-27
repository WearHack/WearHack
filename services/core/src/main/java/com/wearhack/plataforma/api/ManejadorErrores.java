package com.wearhack.plataforma.api;

import com.wearhack.plataforma.ErrorApi;
import com.wearhack.plataforma.ProveedorIdentidadException;
import com.wearhack.plataforma.RecursoNoEncontradoException;
import com.wearhack.plataforma.ReglaDeNegocioException;
import com.wearhack.plataforma.ServicioIaNoDisponibleException;
import jakarta.servlet.http.HttpServletRequest;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Traduce excepciones a {@link ErrorApi}.
 *
 * <p>Nunca devuelve el cuerpo de la peticion ni el detalle interno de un fallo: un
 * mensaje de error puede acabar en un log, y algunos endpoints reciben datos sensibles.
 */
@RestControllerAdvice
class ManejadorErrores {

    private static final Logger log = LoggerFactory.getLogger(ManejadorErrores.class);

    @ExceptionHandler(AuthenticationException.class)
    ResponseEntity<ErrorApi> noAutenticado(AuthenticationException error, HttpServletRequest peticion) {
        return responder(HttpStatus.UNAUTHORIZED,
                "Se necesita un token de acceso valido: falta, es invalido o expiro", peticion);
    }

    @ExceptionHandler(RecursoNoEncontradoException.class)
    ResponseEntity<ErrorApi> noEncontrado(RecursoNoEncontradoException error, HttpServletRequest peticion) {
        return responder(HttpStatus.NOT_FOUND, error.getMessage(), peticion);
    }

    @ExceptionHandler(ReglaDeNegocioException.class)
    ResponseEntity<ErrorApi> reglaDeNegocio(ReglaDeNegocioException error, HttpServletRequest peticion) {
        return responder(HttpStatus.UNPROCESSABLE_CONTENT, error.getMessage(), peticion);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorApi> invalido(MethodArgumentNotValidException error, HttpServletRequest peticion) {
        String mensaje = error.getBindingResult().getFieldErrors().stream()
                .map(campo -> campo.getField() + ": " + campo.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return responder(HttpStatus.BAD_REQUEST, mensaje, peticion);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ErrorApi> ilegible(HttpMessageNotReadableException error, HttpServletRequest peticion) {
        return responder(HttpStatus.BAD_REQUEST, "El cuerpo de la peticion falta o esta mal formado", peticion);
    }

    @ExceptionHandler(ProveedorIdentidadException.class)
    ResponseEntity<ErrorApi> proveedorIdentidad(ProveedorIdentidadException error, HttpServletRequest peticion) {
        log.error("Fallo del proveedor de identidad en {} {}", peticion.getMethod(), peticion.getRequestURI(), error);
        return responder(HttpStatus.BAD_GATEWAY, error.getMessage(), peticion);
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorApi> inesperado(Exception error, HttpServletRequest peticion) {
        // Las del framework ya traen su estado (404 sin ruta, 405, 415...): se respeta.
        if (error instanceof ErrorResponse conEstado) {
            return responder(conEstado.getStatusCode(), conEstado.getBody().getDetail(), peticion);
        }
        log.error("Error no controlado en {} {}", peticion.getMethod(), peticion.getRequestURI(), error);
        return responder(HttpStatus.INTERNAL_SERVER_ERROR, "Error interno inesperado", peticion);
    }

    @ExceptionHandler(ServicioIaNoDisponibleException.class)
    ResponseEntity<ErrorApi> iaNoDisponible(ServicioIaNoDisponibleException error, HttpServletRequest peticion) {
        log.warn("IA no disponible en {} {}: {}", peticion.getMethod(), peticion.getRequestURI(), error.getMessage());
        return responder(HttpStatus.SERVICE_UNAVAILABLE,
                "El analisis no esta disponible ahora. Intentalo de nuevo en unos minutos", peticion);
    }

    private static ResponseEntity<ErrorApi> responder(
            HttpStatusCode estado, String mensaje, HttpServletRequest peticion) {
        return ResponseEntity.status(estado).body(ErrorApi.de(estado, mensaje, peticion.getRequestURI()));
    }
}
