#!/bin/bash
# desplegar.sh - pasa el proyecto a /opt/isp-lab y levanta los contenedores.
# Lo ejecuta Vagrant como root, en cada una de las dos VMs, después de subir
# a /tmp/isp-lab los archivos que le tocan a esa VM.
set -euo pipefail

ORIGEN=/tmp/isp-lab
DESTINO=/opt/isp-lab

# rsync --delete deja el destino igual al repo: lo que se borró en el repo se
# borra acá. Los datos no se pierden, porque viven en volúmenes de Docker y
# no en esta carpeta.
# --checksum compara el contenido (la fecha cambia en cada subida y no sirve) y
# --itemize-changes lista lo que cambió: ">f" es un archivo con contenido nuevo.
# --inplace escribe sobre el archivo que ya está en vez de cambiarlo por uno
# nuevo. Importa para un archivo montado suelto en un contenedor (pg_hba.conf):
# si se lo cambia por otro, el contenedor sigue viendo el viejo.
install -d "$DESTINO"
cambios=$(rsync -a --checksum --delete --inplace --itemize-changes "$ORIGEN"/ "$DESTINO"/)
chmod 600 "$DESTINO/.env"
chmod +x "$DESTINO"/servidor/*.sh "$DESTINO"/servidor/isp 2>/dev/null || true

cd "$DESTINO"
# --build rearma la imagen de FreeRADIUS si cambió su configuración
docker compose up -d --build --remove-orphans

# Alloy, Prometheus y Grafana leen su configuración solo al arrancar, y Docker
# no se entera de que cambió un archivo montado. Si cambió, se reinicia ese
# servicio y nada más. (Solo aplica en la VM donde ese servicio existe.)
servicios=$(docker compose config --services)
for servicio in alloy prometheus grafana; do
  grep -qx "$servicio" <<<"$servicios" || continue
  carpeta=$servicio
  [ "$servicio" = grafana ] && carpeta=grafana/provisioning
  if grep -q -E "^(>f|\*deleting).* $carpeta/" <<<"$cambios"; then
    echo "Cambió la configuración de $servicio: se reinicia."
    docker compose restart "$servicio"
  fi
done

# El exportador SNMP también lee su archivo de autenticación solo al arrancar.
if grep -qx snmp-exporter <<<"$servicios" && grep -q -E "^>f.* prometheus/snmp-auths.yml" <<<"$cambios"; then
  echo "Cambió la autenticación SNMP: se reinicia snmp-exporter."
  docker compose restart snmp-exporter
fi

# PostgreSQL puede releer su lista de accesos sin reiniciarse ni cortar a nadie.
if grep -qx postgres <<<"$servicios" && grep -q -E "^>f.* postgres/pg_hba.conf" <<<"$cambios"; then
  echo "Cambió postgres/pg_hba.conf: PostgreSQL lo relee."
  docker compose exec -T postgres psql -U postgres -qtA -c "SELECT pg_reload_conf()" >/dev/null || true
fi

# El comando de operación queda a mano como "isp" (solo en la VM de la base y el RADIUS).
if grep -qx postgres <<<"$servicios"; then
  ln -sf "$DESTINO/servidor/isp" /usr/local/bin/isp
fi

# La copia temporal ya cumplió, y adentro tiene el .env.
rm -rf "$ORIGEN"

echo
docker compose ps --format "table {{.Name}}\t{{.Status}}"
