package com.wearhack.plataforma.seguridad;

import com.wearhack.plataforma.ProveedorIdentidad;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;

/**
 * El Core como resource server: valida el JWT de Cognito contra el JWKS del User Pool.
 *
 * <p>En el Learner Lab no hay API Gateway delante, asi que esta es la unica validacion. En
 * la arquitectura objetivo queda como defensa en profundidad.
 *
 * <p>Todo exige token salvo los health checks, que los consultan Docker y quien vigila el
 * despliegue sin sesion de usuario.
 */
@Configuration
@EnableConfigurationProperties(CognitoProperties.class)
class SeguridadConfig {

    private static final Logger log = LoggerFactory.getLogger(SeguridadConfig.class);

    private static final String[] RUTAS_PUBLICAS = {
        "/health", "/api/v1/*/health", "/actuator/health", "/actuator/health/**", "/actuator/info",
    };

    @Bean
    SecurityFilterChain cadenaDeSeguridad(HttpSecurity http, EntradaNoAutenticada entrada)
            throws Exception {
        http.csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(sesion ->
                        sesion.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(rutas -> rutas
                        .requestMatchers(RUTAS_PUBLICAS).permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(servidor -> servidor
                        .jwt(Customizer.withDefaults())
                        .authenticationEntryPoint(entrada))
                .exceptionHandling(errores -> errores.authenticationEntryPoint(entrada));
        return http.build();
    }

    @Bean
    JwtDecoder decodificadorJwt(CognitoProperties cognito) {
        if (!cognito.configurado()) {
            log.warn("Cognito no esta configurado (COGNITO_USER_POOL_ID vacio): "
                    + "se rechaza todo token. Solo los health checks responden.");
            return token -> {
                throw new BadJwtException("Cognito no esta configurado");
            };
        }
        if (cognito.clientIds().isEmpty()) {
            // Fallar al arrancar es mejor que aceptar tokens de cualquier app client del pool.
            throw new IllegalStateException(
                    "COGNITO_CLIENT_IDS esta vacio: hay que listar los app clients aceptados");
        }

        NimbusJwtDecoder decodificador = NimbusJwtDecoder.withJwkSetUri(cognito.jwksUri()).build();
        decodificador.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(cognito.emisor()),
                new TokenDeAccesoCognitoValidator(cognito.clientIds())));
        return decodificador;
    }

    @Bean
    ProveedorIdentidad proveedorIdentidad(CognitoProperties cognito) {
        return new CognitoProveedorIdentidad(cognito);
    }
}
