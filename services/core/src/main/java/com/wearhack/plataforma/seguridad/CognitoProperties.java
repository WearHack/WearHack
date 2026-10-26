package com.wearhack.plataforma.seguridad;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * El User Pool de Cognito contra el que se validan los tokens.
 *
 * <p>Sin {@code userPoolId} el Core arranca igual, pero rechaza todo token: es lo que
 * pasa en local mientras nadie haya creado el pool. Nunca deja pasar sin validar.
 *
 * @param region region del User Pool, la misma del Learner Lab
 * @param userPoolId identificador del User Pool, como {@code us-east-1_AbCdEf123}
 * @param clientIds app clients cuyos tokens se aceptan. Un token de otro app client del
 *     mismo pool se rechaza
 */
@ConfigurationProperties("wearhack.cognito")
public record CognitoProperties(String region, String userPoolId, List<String> clientIds) {

    public CognitoProperties {
        region = region == null || region.isBlank() ? "us-east-1" : region.strip();
        userPoolId = userPoolId == null ? "" : userPoolId.strip();
        clientIds = clientIds == null
                ? List.of()
                : clientIds.stream().map(String::strip).filter(id -> !id.isEmpty()).toList();
    }

    public boolean configurado() {
        return !userPoolId.isEmpty();
    }

    /** El {@code iss} que llevan los tokens del pool. */
    public String emisor() {
        return "https://cognito-idp." + region + ".amazonaws.com/" + userPoolId;
    }

    /** Las claves publicas del pool. Se descargan en la primera validacion, no al arrancar. */
    public String jwksUri() {
        return emisor() + "/.well-known/jwks.json";
    }
}
