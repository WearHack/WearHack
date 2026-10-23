# Cognito: User Pool y Google (issues #21 y #22)

El registro y el login van directo del cliente a Cognito (Amplify Flutter). El Core no
gestiona credenciales: valida el token de acceso contra el JWKS del pool y liga el perfil
de negocio al `sub` ([stack, secciones 2 y 3](../../docs/stack-tecnologico-wearhack.md)).

`infra/terraform/` sigue vacio, asi que esto se crea a mano con la AWS CLI desde la
terminal del Learner Lab. Los comandos son idempotentes solo en lo que se lee; crear dos
veces crea dos pools.

## 1. User Pool

Login por correo, verificado por correo. La mayoria de edad **no** va como atributo de
Cognito: es del perfil del Core (`PUT /api/v1/usuarios/me`).

```bash
POOL=$(aws cognito-idp create-user-pool \
  --pool-name wearhack \
  --username-attributes email \
  --auto-verified-attributes email \
  --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}' \
  --account-recovery-setting 'RecoveryMechanisms=[{Priority=1,Name=verified_email}]' \
  --query UserPool.Id --output text)
echo "$POOL"

# Dominio de la Hosted UI. El prefijo es global en la region: anade algo propio.
aws cognito-idp create-user-pool-domain --user-pool-id "$POOL" --domain wearhack-<sufijo>
```

## 2. Google como proveedor federado

En Google Cloud Console (gratis): **APIs & Services > Credentials > OAuth client ID**, tipo
*Web application*, con esta URI de redireccion autorizada:

```
https://wearhack-<sufijo>.auth.us-east-1.amazoncognito.com/oauth2/idpresponse
```

```bash
aws cognito-idp create-identity-provider \
  --user-pool-id "$POOL" \
  --provider-name Google \
  --provider-type Google \
  --provider-details 'client_id=<GOOGLE_CLIENT_ID>,client_secret=<GOOGLE_CLIENT_SECRET>,authorize_scopes=openid email profile' \
  --attribute-mapping 'email=email,name=name,username=sub'
```

El secreto de Google se queda en Cognito: no va en el repo, ni en la app, ni en el Core.

Sign in with Apple queda fuera del MVP (sin iOS).

## 3. App client de la app movil

Publico (sin secreto: va dentro de la app), con la Hosted UI redirigiendo al esquema de la
app. En Android la Hosted UI se abre en Custom Tabs y vuelve por `wearhack://`.

```bash
CLIENTE=$(aws cognito-idp create-user-pool-client \
  --user-pool-id "$POOL" \
  --client-name wearhack-movil \
  --no-generate-secret \
  --explicit-auth-flows ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --supported-identity-providers COGNITO Google \
  --allowed-o-auth-flows-user-pool-client \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid email profile aws.cognito.signin.user.admin \
  --callback-urls 'wearhack://auth/' \
  --logout-urls 'wearhack://signout/' \
  --prevent-user-existence-errors ENABLED \
  --query UserPoolClient.ClientId --output text)
echo "$CLIENTE"
```

## 4. Conectar el Core

En el `.env` del host (nunca en el repo):

```bash
COGNITO_REGION=us-east-1
COGNITO_USER_POOL_ID=<POOL>
COGNITO_CLIENT_IDS=<CLIENTE>
```

El Core acepta **solo tokens de acceso** (`token_use=access`) de los app clients listados.
El token de identidad se rechaza aunque este bien firmado. Sin `COGNITO_USER_POOL_ID`
arranca igual, pero rechaza todo token.

Para eliminar una cuenta (`DELETE /api/v1/usuarios/me`) el Core llama a
`AdminDeleteUser` con las credenciales del host: en el Learner Lab, el perfil de instancia
`LabRole`.

## 5. Comprobar

```bash
# Sin token: 401 con WWW-Authenticate: Bearer
curl -i localhost:8090/api/v1/usuarios/me

# Un usuario de prueba con correo, y su token de acceso
aws cognito-idp sign-up --client-id "$CLIENTE" --username prueba@example.com --password 'Prueba1234'
aws cognito-idp admin-confirm-sign-up --user-pool-id "$POOL" --username prueba@example.com
```

El token se obtiene con la app o con la Hosted UI; `ALLOW_USER_PASSWORD_AUTH` esta
desactivado a proposito para que nadie mande la clave en claro.

## Pendiente

- **Verificar que Cognito y la federacion con Google funcionen dentro del Learner Lab**
  (issue #22). No se ha probado: el lab restringe servicios y las credenciales de la
  sesion caducan.
- Comprobar que `LabRole` permite `cognito-idp:AdminDeleteUser`. Si no, eliminar la cuenta
  responde 502 y el usuario conserva el acceso para reintentar.
- Pasar esto a Terraform cuando `infra/terraform/` deje de estar vacio.
