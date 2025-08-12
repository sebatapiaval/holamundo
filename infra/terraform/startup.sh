#!/usr/bin/env bash
set -euxo pipefail
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Instalar Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Agregar el usuario SSH al grupo docker
usermod -aG docker ${ssh_user} || true

# Habilitar Docker al inicio
systemctl enable docker --now
