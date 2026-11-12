package com.wearhack.usuarios.api;

import com.wearhack.usuarios.DerechosPlan;
import com.wearhack.usuarios.Plan;
import com.wearhack.usuarios.PlanesUsuario;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * El plan del usuario y cuanto le queda de su cuota de IA este mes.
 *
 * <p>Solo lectura: el usuario no puede cambiar su plan desde la API. Lo cambiara la
 * verificacion de la compra en Google Play.
 */
@RestController
@RequestMapping("/api/v1/usuarios/me/plan")
class PlanController {

    private final PlanesUsuario planes;

    PlanController(PlanesUsuario planes) {
        this.planes = planes;
    }

    @GetMapping
    PlanRespuesta obtener(@AuthenticationPrincipal Jwt token) {
        String usuarioId = token.getSubject();
        DerechosPlan derechos = planes.derechos(usuarioId);
        int usadas = planes.solicitudesIaUsadas(usuarioId);
        return new PlanRespuesta(
                derechos.plan(), derechos, usadas, Math.max(0, derechos.solicitudesIaPorMes() - usadas));
    }

    record PlanRespuesta(
            Plan plan, DerechosPlan derechos, int solicitudesIaUsadas, int solicitudesIaRestantes) {}
}
