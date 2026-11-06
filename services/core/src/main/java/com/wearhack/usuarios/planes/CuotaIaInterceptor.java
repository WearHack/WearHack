package com.wearhack.usuarios.planes;

import com.wearhack.usuarios.PlanesUsuario;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * Gasta una solicitud de la cuota antes de las rutas que llaman a la IA, y la devuelve si
 * la respuesta no fue un exito: un recorte sin rostro o la IA caida no gastan cupo.
 *
 * <p>Va como interceptor para no tocar los controladores que ya llaman a la IA.
 */
class CuotaIaInterceptor implements HandlerInterceptor {

    private static final String CONSUMIDA = CuotaIaInterceptor.class.getName() + ".consumida";

    private final PlanesUsuario planes;

    CuotaIaInterceptor(PlanesUsuario planes) {
        this.planes = planes;
    }

    @Override
    public boolean preHandle(HttpServletRequest peticion, HttpServletResponse respuesta, Object handler) {
        if (!"POST".equals(peticion.getMethod())) {
            return true;
        }
        String usuarioId = usuario();
        if (usuarioId == null) {
            return true; // sin token ya lo rechaza la seguridad
        }
        planes.consumirSolicitudIa(usuarioId);
        peticion.setAttribute(CONSUMIDA, usuarioId);
        return true;
    }

    @Override
    public void afterCompletion(
            HttpServletRequest peticion, HttpServletResponse respuesta, Object handler, Exception error) {
        if (peticion.getAttribute(CONSUMIDA) instanceof String usuarioId
                && (error != null || respuesta.getStatus() >= 400)) {
            planes.devolverSolicitudIa(usuarioId);
        }
    }

    private static String usuario() {
        Authentication autenticacion = SecurityContextHolder.getContext().getAuthentication();
        return autenticacion instanceof JwtAuthenticationToken jwt ? jwt.getToken().getSubject() : null;
    }
}
