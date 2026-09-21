package com.wearhack.gateway.seguridad;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

/**
 * Punto de extension para la autenticacion. HOY NO AUTENTICA NADA.
 *
 * <p><strong>Esto es un stub.</strong> Deja pasar cualquier peticion, con o sin
 * token. No lo confundas con seguridad: mientras este asi, el gateway esta
 * abierto y solo puede vivir en local. Avisa en cada arranque para que nadie lo
 * despliegue por descuido.
 *
 * <p>Lo unico que si hace de verdad es borrar las cabeceras de identidad que
 * vengan del cliente. Cuando aqui se valide el token, los servicios de abajo van
 * a confiar en {@code X-WearHack-Sujeto}, y si un cliente pudiera mandarla por su
 * cuenta se haria pasar por quien quisiera. Limpiarla desde el primer dia evita
 * que esa suplantacion exista en algun momento intermedio.
 *
 * <p>Cuando toque implementarlo: validar el JWT, resolver el sujeto y los roles,
 * y poblar {@link #CABECERA_SUJETO} con el valor ya verificado.
 */
@Component
public class AutenticacionGlobalFilter implements GlobalFilter, Ordered {

    private static final Logger log = LoggerFactory.getLogger(AutenticacionGlobalFilter.class);

    /** Identidad ya verificada que el gateway pasa hacia abajo. Nunca la fija el cliente. */
    public static final String CABECERA_SUJETO = "X-WearHack-Sujeto";

    /** Roles ya verificados. Mismo trato que la anterior. */
    public static final String CABECERA_ROLES = "X-WearHack-Roles";

    @PostConstruct
    void avisar() {
        log.warn("La autenticacion del gateway es un STUB: toda peticion pasa sin validar. "
                + "Solo apto para entorno local.");
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest peticion = exchange.getRequest().mutate()
                .headers(cabeceras -> {
                    cabeceras.remove(CABECERA_SUJETO);
                    cabeceras.remove(CABECERA_ROLES);
                })
                .build();

        // TODO(auth): validar el JWT del Authorization, rechazar con 401 si no
        // es valido, y fijar CABECERA_SUJETO y CABECERA_ROLES con lo verificado.

        return chain.filter(exchange.mutate().request(peticion).build());
    }

    @Override
    public int getOrder() {
        // Antes que el ruteo: no tiene sentido decidir a donde va una peticion
        // que vamos a rechazar.
        return Ordered.HIGHEST_PRECEDENCE + 100;
    }
}
