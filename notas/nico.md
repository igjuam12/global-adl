# Notas — Parte 2: FreeRADIUS

**Responsable:** Nico

Escribir **mientras** se trabaja, no al final. Es lo que preguntan en la presentación.

## 1. Qué investigué

### Qué es mi pieza

FreeRADIUS es "la lista de invitados" del ISP. El router (el cliente RADIUS) le pregunta si deja entrar a un abonado, y FreeRADIUS contesta **Access-Accept** (con el plan del abonado) o **Access-Reject**. Después recibe el accounting que manda el router.

- **Cliente** = quien le pregunta al RADIUS: el router. En las pruebas, `radtest` se hace pasar por router.
- **Usuario** = el abonado. El abonado nunca habla con el RADIUS.
- Si el **usuario** no existe o la clave está mal, FreeRADIUS responde Reject **sin decir el motivo**, para no revelar qué usuarios son válidos.
- Si el **cliente** es desconocido o tiene otro secreto, FreeRADIUS **ni contesta**: ignora el paquete (a verificar en la prueba "Secreto distinto").

### Cómo procesa un pedido (lo vi con `-X`)

Cada pedido pasa por **etapas** definidas en el servidor virtual `default` (`sites-enabled/default`). En cada etapa se ejecuta una lista de **módulos**, y cada uno responde `ok`, `noop` (no hizo nada), `updated`, `reject`, etc.

1. **`authorize`**: "¿qué sé de este usuario?". Algún módulo tiene que aportar la contraseña **"known good"** (la guardada) y decidir el `Auth-Type`. Hoy lo hace `files` (archivo `users`); en la etapa 2 lo va a hacer `sql`.
2. **`authenticate`**: "¿la clave que mandó coincide?". Con `Auth-Type = PAP`, el módulo `pap` compara la clave recibida con la guardada.
3. **`post-auth`**: lo que se hace después de aceptar o rechazar. Ahí se va a registrar cada intento en `radpostauth`.

Detalles que aparecieron:

- Sin contraseña conocida → `No Auth-Type found` → Reject.
- Los rechazos se demoran **1 segundo** a propósito, para frenar ataques de fuerza bruta.
- FreeRADIUS **lee su configuración una sola vez, al arrancar**. Si se cambia un archivo, hay que reiniciarlo.

### Cómo se organiza la configuración

En la imagen está en `/etc/freeradius`, y `/etc/raddb` es un enlace a esa carpeta.

| Archivo o carpeta | Para qué |
| --- | --- |
| `radiusd.conf` | Archivo principal, incluye a los demás |
| `clients.conf` | Quién puede preguntar (routers y su secreto) |
| `users` | Usuarios en archivo, los lee el módulo `files` |
| `mods-available` / `mods-enabled` | Módulos disponibles / activados (activar = enlace en `enabled`) |
| `mods-config` | Configuración extra de módulos, por ejemplo las consultas SQL |
| `sites-available` / `sites-enabled` | Servidores virtuales (`default`) con las etapas |
| `dictionary` | Nombres de los atributos, como `Mikrotik-Rate-Limit` |

### Conceptos de Docker que usé

- **Imagen** = la receta (como la ISO). **Contenedor** = la receta en ejecución (como la VM corriendo), pero comparte el kernel del host.
- **Tag** = la versión de la imagen. `latest-3.2` se mueve con el tiempo; una versión exacta (`3.2.10`) no.
- **Bind mount** (`-v origen:destino:ro`): un archivo de la VM aparece dentro del contenedor. La configuración vive afuera (en el repo) y se monta, porque lo que se edita adentro se pierde al recrear el contenedor.
- **VM vs contenedor:** la VM es para otro sistema operativo (por eso MikroTik va en VM); el contenedor, para correr programas de Linux (FreeRADIUS, PostgreSQL, Grafana).

## 2. Alternativas

| Decisión | Opciones | Por qué descarté las otras |
| --- | --- | --- |
| Dónde probar FreeRADIUS | Docker Desktop en Windows · **VM isp-servicios propia** · otra VM Debian | Docker Desktop y otra VM no tienen la IP 10.10.50.10, y el compose publica los puertos en esa IP: habría que adaptarlo. Además, Docker Desktop puede chocar con VirtualBox. |
| Cómo entrar por SSH a la VM | **Reenvío de puertos en el NAT** · adaptador solo-anfitrión | El solo-anfitrión suma un adaptador que no está en la topología del plan |
| Cómo instalar Docker | Paquete `docker.io` de Debian · **repositorio oficial de Docker** · script `get.docker.com` | `docker.io` trae Compose v1 (`docker-compose`), que no entiende `docker compose up -d`. El script es una caja negra que no puedo explicar. |
| Con qué usuario uso Docker | root · **`nico` en el grupo `docker`** | Trabajar todo como root aumenta el impacto de un error |
| Por dónde empezar | Conectar primero la base de Agus · **FreeRADIUS solo, con usuarios en archivo** | Prefiero entender FreeRADIUS sin depender de otra parte, y sumar la base después |
| Versión de la imagen | `latest-3.2` · **`3.2.10`** · `3.2.10-alpine` | `latest-3.2` cambia con el tiempo y cada uno podría integrar con otra versión. Alpine es más liviana pero trae menos herramientas para diagnosticar (sin `bash`). |

## 3. Qué elegí y por qué

- **VM `isp-servicios` propia**, igual a la del plan: lo que anda ahí, anda en la integración sin rehacer nada.
- **Docker desde el repositorio oficial**: versión actual, con `docker compose` v2, y cada paso se puede explicar.
- **`nico` en el grupo `docker`.** Sé que en la práctica equivale a ser root, porque el motor de Docker corre como root. En un laboratorio es aceptable; en un servidor real se cuida.
- **Imagen `freeradius/freeradius-server:3.2.10`** (base Ubuntu), la última 3.2 al 20-nov.
- **Primero FreeRADIUS solo**, con usuarios en archivo, y la base en la etapa 2.

## 4. Qué hice

### VM isp-servicios

- Debian 12.15 netinst, sin escritorio, con servidor SSH. 2 GB de RAM, 2 CPU, disco de 20 GB.
- Adaptador 1: NAT (`enp0s3`, 10.0.2.15 por DHCP, salida a internet por 10.0.2.2).
- Adaptador 2: red interna `isp-servicios` (`enp0s8`).
- IP fija en `/etc/network/interfaces`, **sin gateway**: la VM ya sale a internet por el NAT y solo puede haber una ruta por defecto. Con el `/24`, el router (10.10.50.1) queda en la misma red.

  ```
  allow-hotplug enp0s8
  iface enp0s8 inet static
      address 10.10.50.10/24
  ```

- SSH desde Windows: regla de NAT `ssh, TCP, 127.0.0.1:2222 → 22`, y `ssh -p 2222 nico@127.0.0.1`.
- Docker 29.10.0 y Compose v5.8.0, del repositorio oficial (clave en `/etc/apt/keyrings/docker.asc` y repo en `/etc/apt/sources.list.d/docker.sources`).
- Repo clonado en `~/global-adl`.

#### Comandos para armarla igual

**1. En VirtualBox:** VM `isp-servicios`, Debian 64-bit, sin instalación desatendida, 2048 MB, 2 CPU, disco de 20 GB dinámico. Red: adaptador 1 **NAT**, adaptador 2 **red interna** `isp-servicios`. Regla para entrar por SSH (con la VM apagada, para que quede guardada):

```powershell
VBoxManage modifyvm isp-servicios --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
```

**2. Instalador de Debian:** hostname `isp-servicios`, dominio vacío, interfaz principal `enp0s3`, particionado guiado en todo el disco. En "Selección de programas": sin entorno de escritorio ni GNOME, **con** servidor SSH y utilidades estándar. GRUB en `/dev/sda`.

**3. Entrar desde Windows:**

```powershell
ssh -p 2222 nico@127.0.0.1
```

Si aparece `REMOTE HOST IDENTIFICATION HAS CHANGED!` (porque antes hubo otra VM en ese puerto): `ssh-keygen -R "[127.0.0.1]:2222"` y volver a conectar.

**4. Como root (`su -`): IP fija, Docker y permisos.**

```bash
# IP fija hacia el router, sin gateway (la salida a internet es por el NAT)
cat >> /etc/network/interfaces <<'EOF'

# Red de servicios del ISP: hacia el router (10.10.50.1)
allow-hotplug enp0s8
iface enp0s8 inet static
    address 10.10.50.10/24
EOF
ifup enp0s8

# Clave del repositorio oficial de Docker
apt update
apt install ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Repositorio de Docker (los $(...) completan la versión de Debian y el procesador)
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt update

# Docker y el plugin de compose
apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Usar docker sin ser root (se aplica en un login nuevo)
usermod -aG docker nico
```

**5. Salir de root y del SSH, volver a entrar como `nico` y verificar:**

```bash
ip -br a                 # enp0s8 UP con 10.10.50.10/24
groups                   # tiene que aparecer docker
docker --version
docker compose version
docker run hello-world   # "Hello from Docker!"
```

**6. Clonar el repo:**

```bash
cd ~
git clone https://github.com/igjuam12/global-adl.git
```

### Etapa 1: FreeRADIUS solo (exploración, todavía no está en el repo)

Lo corrí en modo debug con un archivo `users` de prueba montado desde la VM:

```bash
docker run --rm -it --name radius-prueba \
  -v ~/prueba-radius/users:/etc/freeradius/users:ro \
  freeradius/freeradius-server:3.2.10 -X
```

Archivo `users` de prueba:

```
pepe Cleartext-Password := "clave123"
    Mikrotik-Rate-Limit = "256k/512k"

moroso Cleartext-Password := "clave3", Auth-Type := Reject
```

- La primera línea de cada usuario son las condiciones (*check*); las líneas con sangría son lo que se devuelve (*reply*).
- Las pruebas usan el cliente `localhost` que trae la imagen (secreto `testing123`).

| Prueba (`radtest`) | Resultado | Qué mostró el `-X` |
| --- | --- | --- |
| `pepe` sin estar en `users` | Reject | `[files] = noop` → `No Auth-Type found` |
| `pepe clave123` | **Accept** + `Mikrotik-Rate-Limit = "256k/512k"` | `files: Matched entry pepe` → `Auth-Type = PAP` → `User authenticated successfully` |
| `moroso clave3` (clave correcta) | Reject | `Auth-Type already set` → `Auth-Type = Reject`: **no compara la clave** |
| `pepe otraclave` | Reject | `Auth-Type = PAP` → `Passwords don't match` |

**Conclusión:** el moroso se rechaza por **quién es**, en `authorize`, antes de mirar la contraseña. La clave incorrecta se rechaza en `authenticate`. Desde afuera los dos son iguales; el `-X` muestra la diferencia.

## 5. Qué falló y cómo lo diagnostiqué

| Síntoma | Cómo lo diagnostiqué (comando o log) | Causa | Solución |
| --- | --- | --- | --- |
| SSH: `REMOTE HOST IDENTIFICATION HAS CHANGED!` | El mensaje marca la línea de `known_hosts` en conflicto, para `[127.0.0.1]:2222` | Ese puerto ya se había usado con una VM de Servidores, y la VM nueva tiene otra huella | `ssh-keygen -R "[127.0.0.1]:2222"`. La huella aceptada después era la misma que mostraba la advertencia: no era un ataque. |
| Las MAC de `ip -br link` no coincidían con las de mi captura de VirtualBox | `VBoxManage showvminfo isp-servicios --machinereadable` | Había recreado la VM después de la captura: MAC nuevas | Ninguna. Lección: verificar contra el estado actual, no contra una captura vieja. |
| `ping 10.10.50.1` → `Destination Host Unreachable` | El error lo genera la propia VM (`From 10.10.50.10`) | Nadie responde ARP: el router todavía no existe | Esperado. Va a ser la primera prueba cuando esté el router. |
| Después de `exit`, se abrió `nano` diciendo "no es de escritura" | El prompt había vuelto a `nico` (`$`) | Había pegado `su -` y `nano …` juntos: la línea de nano quedó pendiente y se ejecutó como `nico` | Salir con Ctrl+X. El archivo estaba intacto. |
| Agregué un usuario a `users` dentro del contenedor y seguía rechazándolo | El `-X` no mostraba `Matched entry` | FreeRADIUS lee la configuración solo al arrancar. Además, con `--rm`, reiniciar borraba el cambio. | Archivo en la VM montado con `-v` y reinicio del contenedor |

## 6. Cómo usé la IA

Usé Claude como guía paso a paso. Las decisiones las tomé yo: para cada una me dio 2 o 3 opciones con ventajas y desventajas. Cada comando y cada línea me los explicó antes de ejecutarlos.

Qué respondió mal y cómo me di cuenta:

1. **Alerta falsa sobre `/etc/raddb`.** Al ver `/etc/freeradius` en el log, la IA avisó que los montajes del compose (en `/etc/raddb/…`) no iban a funcionar. Lo verifiqué con `ls -ld /etc/raddb /etc/freeradius`: `/etc/raddb` es un enlace a `/etc/freeradius`, así que los montajes sí funcionan.
2. **Chequeo de MAC con un dato viejo.** Me dijo que la MAC de `enp0s8` iba a terminar en `6c:f8:6d` (de mi captura) y no coincidió. Con `VBoxManage showvminfo` vimos que la VM tenía otras MAC porque yo la había recreado. La IA se basó en información que ya no era actual.
3. **Coordinación innecesaria.** Me sugirió preguntarle al grupo quién armaba la VM isp-servicios, cuando ya habíamos acordado trabajar de forma independiente. Se lo marqué y lo corrigió: con los datos del plan, cada uno puede armar la suya.

## Pendientes

- [ ] Decidir cómo dar de alta al router: `clients.conf` o la tabla `nas` de la base
- [ ] Armar mi bloque del `docker-compose.yml` con la imagen `3.2.10` y los archivos montados desde `freeradius/`
- [ ] Etapa 2: módulo `sql` contra PostgreSQL (abonado1 Accept con su plan, moroso y clave incorrecta Reject, intentos en `radpostauth`)
- [ ] Verificar la prueba "Secreto distinto": ¿el RADIUS ignora el pedido?
