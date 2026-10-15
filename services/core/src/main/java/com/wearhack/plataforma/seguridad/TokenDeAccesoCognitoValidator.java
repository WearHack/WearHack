package com.wearhack.plataforma.seguridad;

import java.util.List;
import java.util.Set;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2ErrorCodes;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * Lo que la validacion estandar no mira y Cognito necesita.
 *
 * <p>Cognito firma con las mismas claves el token de identidad y el de acceso, asi que la
 * firma y el emisor no bastan para distinguirlos. Al Core solo se le habla con el de
 * acceso ({@code token_use=access}).
 *
 * <p>El token de acceso de Cognito no trae {@code aud}: el app client va en
 * {@code client_id}. Sin comprobarlo, cualquier app client del pool, incluido uno creado
 * para otra cosa, tendria acceso al Core.
 */
class TokenDeAccesoCognitoValidator implements OAuth2TokenValidator<Jwt> {

    private final Set<String> clientIds;

    TokenDeAccesoCognitoValidator(List<String> clientIds) {
        this.clientIds = Set.copyOf(clientIds);
    }

    @Override
    public OAuth2TokenValidatorResult validate(Jwt token) {
        if (!"access".equals(token.getClaimAsString("token_use"))) {
            return fallo("Se esperaba un token de acceso de Cognito");
        }
        String clientId = token.getClaimAsString("client_id");
        if (clientId == null || !clientIds.contains(clientId)) {
            return fallo("El token es de un app client no autorizado");
        }
        return OAuth2TokenValidatorResult.success();
    }

    private static OAuth2TokenValidatorResult fallo(String descripcion) {
        return OAuth2TokenValidatorResult.failure(
                new OAuth2Error(OAuth2ErrorCodes.INVALID_TOKEN, descripcion, null));
    }
}
