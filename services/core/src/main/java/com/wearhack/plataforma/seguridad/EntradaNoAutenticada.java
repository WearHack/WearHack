package com.wearhack.plataforma.seguridad;

import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerExceptionResolver;

/**
 * Respuesta a una peticion sin token valido.
 *
 * <p>La de Spring pone el 401 y la cabecera {@code WWW-Authenticate} del estandar, pero
 * deja el cuerpo vacio. El cuerpo lo escribe el manejador global de errores, para que un
 * 401 tenga la misma forma JSON que cualquier otro error.
 */
@Component
class EntradaNoAutenticada implements AuthenticationEntryPoint {

    private final AuthenticationEntryPoint estandar = new BearerTokenAuthenticationEntryPoint();
    private final HandlerExceptionResolver resolutor;

    EntradaNoAutenticada(@Qualifier("handlerExceptionResolver") HandlerExceptionResolver resolutor) {
        this.resolutor = resolutor;
    }

    @Override
    public void commence(
            HttpServletRequest peticion, HttpServletResponse respuesta, AuthenticationException error)
            throws IOException, ServletException {
        estandar.commence(peticion, respuesta, error);
        resolutor.resolveException(peticion, respuesta, null, error);
    }
}
