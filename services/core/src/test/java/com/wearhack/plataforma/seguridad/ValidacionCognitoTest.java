package com.wearhack.plataforma.seguridad;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.BadJwtException;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Lo que hace distinto a Cognito de un emisor OIDC cualquiera: tipo de token, app client y
 * como se arma el emisor. La firma y el vencimiento los valida Spring Security.
 */
class ValidacionCognitoTest {

    private static final String CLIENTE = "cliente-app-movil";

    private final TokenDeAccesoCognitoValidator validador =
            new TokenDeAccesoCognitoValidator(List.of(CLIENTE));

    @Test
    void aceptaUnTokenDeAccesoDelClienteAutorizado() {
        assertThat(validador.validate(token(Map.of("token_use", "access", "client_id", CLIENTE)))
                .hasErrors()).isFalse();
    }

    @Test
    void rechazaElTokenDeIdentidad() {
        // El de identidad lleva aud en vez de client_id y no sirve para llamar a la API.
        assertThat(validador.validate(token(Map.of("token_use", "id", "aud", CLIENTE)))
                .hasErrors()).isTrue();
    }

    @Test
    void rechazaOtroAppClientDelMismoPool() {
        assertThat(validador.validate(token(Map.of("token_use", "access", "client_id", "otro")))
                .hasErrors()).isTrue();
    }

    @Test
    void rechazaUnTokenSinClientId() {
        assertThat(validador.validate(token(Map.of("token_use", "access"))).hasErrors()).isTrue();
    }

    @Test
    void elEmisorYElJwksSalenDeLaRegionYElPool() {
        var cognito = new CognitoProperties("us-east-1", "us-east-1_Abc123", List.of(CLIENTE));

        assertThat(cognito.emisor()).isEqualTo("https://cognito-idp.us-east-1.amazonaws.com/us-east-1_Abc123");
        assertThat(cognito.jwksUri()).isEqualTo(cognito.emisor() + "/.well-known/jwks.json");
    }

    @Test
    void losValoresVaciosDelEntornoNoCuentanComoConfiguracion() {
        // COGNITO_CLIENT_IDS="" llega como una lista con una cadena vacia.
        var cognito = new CognitoProperties(" ", " ", List.of(""));

        assertThat(cognito.configurado()).isFalse();
        assertThat(cognito.clientIds()).isEmpty();
        assertThat(cognito.region()).isEqualTo("us-east-1");
    }

    @Test
    void sinPoolSeRechazaTodoToken() {
        var decodificador = new SeguridadConfig()
                .decodificadorJwt(new CognitoProperties(null, null, null));

        assertThatThrownBy(() -> decodificador.decode("cualquier.cosa.firmada"))
                .isInstanceOf(BadJwtException.class);
    }

    @Test
    void conPoolPeroSinAppClientsNoArranca() {
        var cognito = new CognitoProperties("us-east-1", "us-east-1_Abc123", List.of());

        assertThatThrownBy(() -> new SeguridadConfig().decodificadorJwt(cognito))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("COGNITO_CLIENT_IDS");
    }

    private static Jwt token(Map<String, Object> claims) {
        return Jwt.withTokenValue("t")
                .header("alg", "RS256")
                .subject("usuario-1")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(300))
                .claims(c -> c.putAll(claims))
                .build();
    }
}
