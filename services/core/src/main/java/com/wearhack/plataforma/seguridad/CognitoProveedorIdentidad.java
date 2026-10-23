package com.wearhack.plataforma.seguridad;

import com.wearhack.plataforma.ProveedorIdentidad;
import com.wearhack.plataforma.ProveedorIdentidadException;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.cognitoidentityprovider.CognitoIdentityProviderClient;
import software.amazon.awssdk.services.cognitoidentityprovider.model.UserNotFoundException;

/**
 * Borra cuentas del User Pool con {@code AdminDeleteUser}.
 *
 * <p>Las credenciales salen de la cadena por defecto del SDK: en el host EC2 del Learner
 * Lab, el perfil de instancia ({@code LabRole}). El cliente se crea en el primer uso, asi
 * que el Core arranca aunque no haya credenciales de AWS, como en local.
 */
class CognitoProveedorIdentidad implements ProveedorIdentidad {

    private static final Logger log = LoggerFactory.getLogger(CognitoProveedorIdentidad.class);

    private final CognitoProperties cognito;
    private volatile CognitoIdentityProviderClient cliente;

    CognitoProveedorIdentidad(CognitoProperties cognito) {
        this.cognito = cognito;
    }

    @Override
    public void eliminarCuenta(String nombreUsuario) {
        if (!cognito.configurado()) {
            throw new ProveedorIdentidadException("Cognito no esta configurado", null);
        }
        try {
            cliente().adminDeleteUser(peticion -> peticion
                    .userPoolId(cognito.userPoolId())
                    .username(nombreUsuario));
        } catch (UserNotFoundException yaNoExiste) {
            // Un reintento despues de un borrado que si llego a Cognito.
            log.info("La cuenta ya no existia en Cognito");
        } catch (SdkException error) {
            throw new ProveedorIdentidadException("No se pudo eliminar la cuenta en Cognito", error);
        }
    }

    private CognitoIdentityProviderClient cliente() {
        if (cliente == null) {
            synchronized (this) {
                if (cliente == null) {
                    cliente = CognitoIdentityProviderClient.builder()
                            .region(Region.of(cognito.region()))
                            .build();
                }
            }
        }
        return cliente;
    }

    @PreDestroy
    void cerrar() {
        if (cliente != null) {
            cliente.close();
        }
    }
}
