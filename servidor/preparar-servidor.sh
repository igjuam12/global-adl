#!/bin/bash
# preparar-servidor.sh - deja una VM Debian lista: hora, NTP y Docker.
# Lo ejecuta Vagrant como root en isp-servicios y en isp-monitoreo. Se puede
# repetir sin romper nada.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- 1. Zona horaria -----------------------------------------------------------
# Los contenedores guardan todo en UTC; esto es para que los comandos que
# corremos a mano en la VM muestren la hora de acá.
timedatectl set-timezone America/Argentina/Buenos_Aires

# --- 2. Una sola hora para todo el ISP (NTP) -----------------------------------
# La VM toma la hora de internet y se la puede dar a los equipos de la red
# de servicios. El router se la pide a isp-servicios (10.10.50.10). Sin esto
# cada equipo confía en su propio reloj, y el accounting y los logs quedan con
# horarios que no coinciden (el router llegó a estar 46 minutos adelantado).
# Es un servicio del sistema y no un contenedor: la hora es del servidor.
if ! command -v chronyd >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq chrony >/dev/null
fi
cat > /etc/chrony/conf.d/isp.conf <<'EOF'
# Dar la hora a los equipos de la red de servicios (el router)
allow 10.10.50.0/24
# Si se corta internet, seguir dando la hora con el reloj propio
local stratum 10
EOF
systemctl restart chrony
systemctl enable chrony >/dev/null 2>&1

# --- 3. Docker ------------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  echo "Docker ya está instalado: $(docker --version)"
  exit 0
fi

echo "Instalando Docker desde el repositorio oficial..."
apt-get update -qq
apt-get install -y -qq ca-certificates curl rsync >/dev/null

# La clave con la que Docker firma sus paquetes, y su repositorio para Debian 12
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null

# Para poder usar docker sin sudo al entrar con "vagrant ssh"
usermod -aG docker vagrant

docker --version
docker compose version
