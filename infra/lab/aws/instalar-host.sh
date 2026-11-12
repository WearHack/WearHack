#!/bin/bash
# user-data de la EC2 (Amazon Linux 2023). Instala Docker, Compose y git, clona el repo
# con el token de SSM e instala el timer que despliega develop cada 5 minutos.
set -euxo pipefail
dnf install -y docker git
systemctl enable --now docker
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
curl -fsSL https://github.com/docker/buildx/releases/download/v0.29.1/buildx-v0.29.1.linux-amd64 \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/*

mkdir -p /opt/wearhack
set +x  # el token no va al log de cloud-init
T=$(aws ssm get-parameter --region us-east-1 --name /wearhack/GITHUB_TOKEN --with-decryption \
  --query Parameter.Value --output text)
git -c http.extraHeader="Authorization: Basic $(printf 'x-access-token:%s' "$T" | base64 -w0)" \
  clone --quiet --branch develop https://github.com/WearHack/WearHack.git /opt/wearhack/repo
unset T
set -x
install -m 755 /opt/wearhack/repo/infra/lab/aws/desplegar.sh /opt/wearhack/desplegar.sh

cat > /etc/systemd/system/wearhack-desplegar.service <<'EOF'
[Unit]
Description=WearHack: despliega develop si hay commit nuevo
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/wearhack/desplegar.sh
TimeoutStartSec=30min
EOF
cat > /etc/systemd/system/wearhack-desplegar.timer <<'EOF'
[Unit]
Description=WearHack: revisa develop cada 5 minutos

[Timer]
OnBootSec=2min
OnUnitInactiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable wearhack-desplegar.timer
# Primer despliegue: forzado, aunque el checkout ya este en el ultimo commit.
FORZAR=1 /opt/wearhack/desplegar.sh
systemctl start wearhack-desplegar.timer
