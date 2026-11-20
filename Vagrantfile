# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Vagrantfile - crea y prepara las dos VMs Debian del proyecto.
#
#   isp-servicios   lo que hace funcionar al ISP: PostgreSQL y FreeRADIUS
#   isp-monitoreo   lo que lo mira: Alloy, Prometheus, Loki y Grafana
#
# Van separadas a propósito: si se cae la VM de servicios, el tablero sigue
# vivo en la otra y lo muestra.
#
# Uso, parado en la raíz del repo:
#   vagrant up                    crea las dos VMs, instala Docker, sube el proyecto y lo levanta
#   vagrant provision             vuelve a subir el proyecto y aplica los cambios (después de un git pull)
#   vagrant ssh isp-servicios     entra a una VM (o isp-monitoreo)
#   vagrant halt                  las apaga          vagrant destroy   las borra enteras
#
# Grafana queda en http://localhost:3000

MAQUINAS = {
  "isp-servicios" => {
    ip: "10.10.50.10", memoria: 1024,
    compose: "docker-compose.yml",
    carpetas: %w[postgres freeradius servidor],
    claves: %w[POSTGRES_ADMIN_PASSWORD RADIUS_DB_PASSWORD GRAFANA_DB_PASSWORD RADIUS_SHARED_SECRET],
  },
  "isp-monitoreo" => {
    ip: "10.10.50.20", memoria: 1536,
    compose: "docker-compose.monitoreo.yml",
    carpetas: %w[alloy prometheus grafana servidor],
    claves: %w[GRAFANA_ADMIN_PASSWORD GRAFANA_DB_PASSWORD GESTION_IP],
    grafana: true,
  },
}

Vagrant.configure("2") do |config|
  # La misma base para todos, con la versión fija (nada de "la última")
  config.vm.box = "debian/bookworm64"
  config.vm.box_version = "12.20250126.1"
  config.vm.box_check_update = false

  # La carpeta compartida por defecto necesita rsync en Windows, que no viene. Los
  # archivos se suben con el aprovisionador "file", que usa la misma conexión SSH.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  MAQUINAS.each do |nombre, m|
    config.vm.define nombre do |vm|
      vm.vm.hostname = nombre

      # Adaptador 1: NAT. Lo pone Vagrant solo: por ahí sale a internet y entra el SSH.
      # Adaptador 2: la red interna del ISP, con IP fija.
      vm.vm.network "private_network", ip: m[:ip], netmask: "255.255.255.0",
                    virtualbox__intnet: "isp-servicios"

      # Grafana se abre desde el navegador de la notebook. Solo escucha en la propia PC.
      if m[:grafana]
        vm.vm.network "forwarded_port", guest: 3000, host: 3000, host_ip: "127.0.0.1", id: "grafana"
      end

      vm.vm.provider "virtualbox" do |vb|
        vb.name = nombre
        vb.memory = m[:memoria]
        vb.cpus = 2
        vb.customize ["modifyvm", :id, "--groups", "/proyecto-radius"]
      end

      # 1. Preparar la VM: zona horaria, servicio de hora (NTP) y Docker
      vm.vm.provision "preparar-servidor", type: "shell", path: "servidor/preparar-servidor.sh"

      # 2. Subir a una carpeta temporal limpia solo lo que usa esta VM
      vm.vm.provision "limpiar", type: "shell",
                      inline: "rm -rf /tmp/isp-lab && install -d -o vagrant -g vagrant /tmp/isp-lab"
      vm.vm.provision "subir-compose", type: "file", source: m[:compose],
                      destination: "/tmp/isp-lab/docker-compose.yml"
      m[:carpetas].each do |carpeta|
        vm.vm.provision "subir-#{carpeta}", type: "file", source: carpeta,
                        destination: "/tmp/isp-lab/#{carpeta}"
      end
      # Las contraseñas van en .env, que no se versiona. Si no existe, se usan las de laboratorio.
      vm.vm.provision "subir-env", type: "file",
                      source: (File.exist?(File.join(__dir__, ".env")) ? ".env" : ".env.example"),
                      destination: "/tmp/isp-lab/.env"
      # Cada VM se queda solo con las claves que usa: el monitoreo no recibe la del
      # administrador de la base ni el secreto del RADIUS. El archivo queda a nombre
      # del usuario vagrant, para poder usar "docker compose" sin sudo en la VM.
      vm.vm.provision "filtrar-env", type: "shell",
                      inline: "grep -E '^(#{m[:claves].join('|')})=' /tmp/isp-lab/.env > /tmp/isp-lab/.env.solo && mv /tmp/isp-lab/.env.solo /tmp/isp-lab/.env && chown vagrant:vagrant /tmp/isp-lab/.env"

      # 3. Pasarlo a su lugar y levantar los contenedores
      vm.vm.provision "desplegar", type: "shell", path: "servidor/desplegar.sh"
    end
  end
end
