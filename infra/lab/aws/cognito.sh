#!/bin/bash
# CloudShell: crea (o reusa) el User Pool "wearhack", su dominio y el app client movil,
# segun infra/cognito/README.md, y deja los IDs en SSM para el Core. Sin Google (falta
# el OAuth client de Google Cloud, #22). Imprime los valores para el --dart-define.
set -euo pipefail
R=us-east-1
POOL=$(aws cognito-idp list-user-pools --max-results 60 --region $R \
  --query "UserPools[?Name=='wearhack'].Id | [0]" --output text)
if [ "$POOL" = "None" ] || [ -z "$POOL" ]; then
  POOL=$(aws cognito-idp create-user-pool --region $R \
    --pool-name wearhack \
    --username-attributes email \
    --auto-verified-attributes email \
    --policies 'PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}' \
    --account-recovery-setting 'RecoveryMechanisms=[{Priority=1,Name=verified_email}]' \
    --query UserPool.Id --output text)
fi
CUENTA=$(aws sts get-caller-identity --query Account --output text)
DOMINIO=wearhack-${CUENTA: -6}
DOM_ACTUAL=$(aws cognito-idp describe-user-pool --user-pool-id "$POOL" --region $R \
  --query UserPool.Domain --output text)
if [ "$DOM_ACTUAL" = "None" ] || [ -z "$DOM_ACTUAL" ]; then
  aws cognito-idp create-user-pool-domain --user-pool-id "$POOL" --domain "$DOMINIO" --region $R >/dev/null
else
  DOMINIO=$DOM_ACTUAL
fi
CLIENTE=$(aws cognito-idp list-user-pool-clients --user-pool-id "$POOL" --region $R \
  --query "UserPoolClients[?ClientName=='wearhack-movil'].ClientId | [0]" --output text)
if [ "$CLIENTE" = "None" ] || [ -z "$CLIENTE" ]; then
  CLIENTE=$(aws cognito-idp create-user-pool-client --region $R \
    --user-pool-id "$POOL" \
    --client-name wearhack-movil \
    --no-generate-secret \
    --explicit-auth-flows ALLOW_USER_SRP_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --supported-identity-providers COGNITO \
    --allowed-o-auth-flows-user-pool-client \
    --allowed-o-auth-flows code \
    --allowed-o-auth-scopes openid email profile aws.cognito.signin.user.admin \
    --callback-urls 'wearhack://auth/' \
    --logout-urls 'wearhack://signout/' \
    --prevent-user-existence-errors ENABLED \
    --query UserPoolClient.ClientId --output text)
fi
# No son secretos (van dentro de la app): String, no SecureString. desplegar.sh los lee.
for par in "COGNITO_REGION=$R" "COGNITO_USER_POOL_ID=$POOL" "COGNITO_CLIENT_IDS=$CLIENTE"; do
  aws ssm put-parameter --region $R --name "/wearhack/${par%%=*}" --type String \
    --value "${par#*=}" --overwrite >/dev/null
done
echo "COGNITO_REGION=$R"
echo "COGNITO_USER_POOL_ID=$POOL"
echo "COGNITO_CLIENT_ID=$CLIENTE"
echo "COGNITO_DOMINIO=$DOMINIO.auth.$R.amazoncognito.com"
