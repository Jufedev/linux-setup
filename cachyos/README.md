# CachyOS + KDE — instalación y post-instalación

Runbook para dejar esta máquina lista: **CachyOS con KDE Plasma vanilla (Breeze stock)**,
driver NVIDIA funcionando y el distrobox del pipeline andando.

> **Por qué este setup es tan chico.** CachyOS ya trae de fábrica casi todo lo que los
> setups de `arch/` y `fedora/` de este repo tenían que construir a mano. El script solo
> hace lo que la distro **no** hace. El detalle está en
> [Lo que este setup NO hace](#lo-que-este-setup-no-hace-y-por-qué).

---

## 1. En el instalador — las decisiones que no se deshacen

El instalador gráfico de CachyOS pregunta todo esto. Lo que elijas acá no se cambia
después sin reinstalar (o sin bastante trabajo).

| Pantalla | Qué elegir | Por qué |
|---|---|---|
| **Sistema de archivos** | **Btrfs** | Es el default y es lo que habilita los snapshots. Sin Btrfs no hay red de seguridad |
| **Escritorio** | **KDE** | Ningún escritorio viene preseleccionado: hay que marcarlo |
| **Bootloader** | **GRUB** o **Limine** | Los dos soportan snapshots booteables. Si no tocás nada sale **Limine**, que trae la integración de fábrica. GRUB es el más conocido si algo se rompe |
| **Teclado** | **English (US, alt. intl.)** = `us altgr-intl` | Es lo que permite escribir `ñ á é ü` con teclado físico US. Elegilo acá y no hace falta configurarlo después |
| **Paquetes** | Destildá lo que no vayas a usar | El "debloat" se hace **acá**, no con un script. Son grupos con checkbox |

> **La ISO trae dos kernels**: `linux-cachyos` (7.0.x, el default) y `linux-cachyos-lts`
> (6.18.x). El 7.0 tiene una **regresión conocida de suspend/resume (s2idle) en
> Blackwell**. En un desktop pesa poco, pero si al volver de suspender se cuelga,
> booteá el LTS desde el menú del bootloader.

---

## 2. Después del primer boot — verificar ANTES de confiar

Esta máquina tiene la **iGPU deshabilitada en BIOS**: si el driver de video falla, no hay
una segunda salida de imagen para debuggear. Verificá antes de dar nada por hecho.

```bash
# 1. ¿El driver propietario está andando?
nvidia-smi

# 2. ¿Qué perfil de hardware aplicó CachyOS?
chwd --list-installed

# 3. ¿Nouveau quedó afuera? (no debería listar nada cargado)
lsmod | rg -i 'nouveau|nova_'

# 4. ¿Hay snapshots?
snapper -c root list
```

Si `nvidia-smi` responde con la tabla de la GPU, ganaste: `chwd` instaló
`linux-cachyos-nvidia-open` **precompilado** y no hay nada más que hacer con el driver.

Si **`snapper -c root list` falla o no existe**, los snapshots no están armados. El
instalador crea un snapshot inicial pero *se saltea en silencio* si falta el paquete:

```bash
sudo pacman -S cachyos-snapper-support
```

---

## 3. Correr el setup

```bash
git clone https://github.com/Jufedev/linux-setup.git ~/linux-setup
cd ~/linux-setup
bash cachyos/scripts/postinstall.sh --all
```

Es idempotente: se puede re-correr sin romper nada. Log en
`~/.local/state/cachyos-setup.log`.

| Flag | Qué hace |
|---|---|
| `--all` | Los dos módulos de abajo |
| `--apps` | `podman` + `distrobox` (los necesita el pipeline) y `microsoft-edge-stable-bin` (AUR, vía `paru`). **Pide confirmación**: ver abajo |
| `--firewall` | Endurece `ufw`: deny incoming, allow outgoing, lo activa y **verifica las políticas reales**, no solo que esté encendido |

> **`--apps` no es desatendido.** El paso de AUR corre `paru` sin `--noconfirm`, así que te
> muestra el PKGBUILD y espera tu confirmación. Es a propósito: un PKGBUILD de AUR es
> código de la comunidad que se ejecuta al compilar, y ese prompt es el único lugar donde
> podés mirar qué hace. Es un paquete, una vez.
>
> El primer paso de cualquier módulo que instale paquetes corre **`pacman -Syu`** (upgrade
> completo, no solo sincronizar la base). Instalar contra un índice nuevo sin actualizar el
> sistema es un *partial upgrade*, que Arch documenta como no soportado. Si el `-Syu` falla,
> el script **no instala nada** en vez de dejar el sistema mezclado.

Sin argumentos abre un menú interactivo.

**SSH para GitHub** (sin tokens), aparte y cuando quieras:

```bash
bash shared/ssh-github.sh
```

---

## 4. Proyectos en distrobox

Los proyectos no se instalan en el host: cada uno corre en su propio distrobox con su
toolchain adentro. El host queda limpio y un proyecto no arrastra las dependencias del
otro. Para eso están `podman` y `distrobox` en el módulo `--apps`.

El patrón, con la imagen que defina cada proyecto:

```bash
cd ~/Projects/<proyecto>
podman build -t <proyecto>-env -f Containerfile .
distrobox create --name <proyecto> --image localhost/<proyecto>-env:latest --nvidia
distrobox enter <proyecto>
```

> **`--nvidia` se decide al crear, no después.** Sin ese flag el contenedor no ve CUDA
> ni NVENC por más que `nvidia-smi` ande perfecto en el host — y no se le puede agregar
> a un distrobox ya creado: hay que borrarlo y rehacerlo. Si el proyecto toca la GPU,
> para cómputo o para video, ponelo desde el principio.

Verificá que la GPU entró **antes** de construir nada encima:

```bash
distrobox enter <proyecto> -- nvidia-smi
```

> **Para cualquier proyecto de video en esta máquina**: en NVIDIA la VAAPI de *encode*
> no existe (el bridge es solo decode). Si el código ramifica entre VAAPI y un fallback
> por software, hace falta una rama **NVENC** (`h264_nvenc`) o vas a terminar codificando
> en CPU sin enterarte.

---

## 5. Si arrancás a pantalla negra

**Empezá por acá, sirve con cualquier bootloader:** en el menú de arranque, **elegí un
snapshot anterior** o el kernel **LTS**. No hay que escribir nada y resuelve la mayoría
de los casos. Si el menú no aparece, mantené apretado `Shift` (GRUB) o tocá una flecha
apenas prende (Limine).

Si necesitás una consola de rescate, hay que agregar parámetros de kernel a mano, **y el
cómo depende del bootloader que elegiste en la instalación**:

| Bootloader | Cómo editar la entrada |
|---|---|
| **GRUB** | `e` sobre la entrada → agregá al final de la línea que empieza con `linux` → `Ctrl+X` para bootear |
| **Limine** | `e` sobre la entrada → editás su config → agregás a `KERNEL_CMDLINE` → `Enter`/`F10` para bootear |

Los parámetros a agregar, en los dos casos:

```
nouveau.modeset=1 modprobe.blacklist=nvidia 3
```

Eso bootea **una sola vez** a una consola de texto con nouveau vivo. Desde ahí reinstalá
el driver con `chwd` o revertí lo último que hiciste.

> **Anotá qué bootloader elegiste** cuando instales. Buscar los atajos del bootloader
> equivocado con la pantalla en negro es exactamente el momento en que no querés estar
> averiguándolo.

**Lifeboat final**, si no llegás ni a la consola: reactivá la iGPU en BIOS
(`Settings → IO Ports → Integrated Graphics`) y enchufá el monitor a la placa madre.

---

## Lo que este setup NO hace (y por qué)

Auditado el 2026-07-27 contra `cachyos-desktop-linux-260628.iso`. **No re-agregues estos
módulos**: cada uno se sacó con evidencia.

| Lo que hacían `arch/` y `fedora/` | Quién lo hace ahora |
|---|---|
| Instalar el driver NVIDIA (`nvidia-open-dkms` + headers por kernel) | **`chwd`**: instala `${kernel}-nvidia-open` **precompilado** para cada kernel `linux-cachyos` instalado. Sin DKMS |
| `blacklist nouveau` a mano | El paquete `nvidia-utils`, en `/usr/lib/modprobe.d/nvidia-utils.conf` — y también bloquea `nova_core` / `nova_drm` |
| Agregar los módulos NVIDIA al initramfs | **`chwd`**, en `/etc/mkinitcpio.conf.d/10-chwd.conf` (además saca el hook `kms`) |
| `nvidia_drm.modeset=1` en la línea del kernel | Innecesario: es el default del módulo abierto desde la serie 560 |
| Instalar KDE | Viene con la ISO |
| Agregar los repos de CachyOS | Es CachyOS |
| Instalar un helper de AUR (`yay`) | **`paru`** viene de fábrica |
| Instalar fuentes | Vienen Noto, Noto CJK, Liberation, DejaVu, Cantarell, OpenSans y **`ttf-meslo-nerd`** (Nerd Font para la terminal) |
| Configurar las fuentes de KDE | Dos clics en Preferencias del Sistema |
| Instalar `flameshot` | Vienen `flameshot` **y** `spectacle` |
| Instalar `ufw` | Viene instalado — pero **inerte**. Activarlo sí lo hace este script |
| El look macOS (`plasma6macos`) | **Descartado.** Se eligió KDE vanilla: en KDE la personalización es nativa, sin extensiones de terceros que se rompan |

> **`flatpak` NO viene** en CachyOS (al revés que en Fedora). Por eso Edge se instala
> desde AUR y no como Flatpak: `paru` ya está, `flatpak` habría que instalarlo.
