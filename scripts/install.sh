#!/usr/bin/env bash
# ============================================================================
# Arch Linux — Instalación base (UEFI / GPT)
# Ejecutar desde el USB live de Arch: bash install.sh
# ============================================================================
set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${B}[INFO]${NC}  $1"; }
ok()    { echo -e "${G}[OK]${NC}    $1"; }
warn()  { echo -e "${Y}[WARN]${NC}  $1"; }
fail()  { echo -e "${R}[FAIL]${NC}  $1"; exit 1; }

# ── Validaciones iniciales ─────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && fail "Ejecuta este script como root"
[[ ! -d /sys/firmware/efi ]] && fail "Este script requiere modo UEFI — reinicia en modo UEFI desde el BIOS"

REPO_URL="https://github.com/Jufedev/archlinux-setup.git"

# ── Preparación del entorno live ──────────────────────────────────────────
info "Verificando conexión a internet..."
ping -c 1 -W 3 archlinux.org &>/dev/null || fail "Sin conexión a internet — conecta con: iwctl station wlan0 connect TU_SSID"
ok "Internet disponible"

info "Sincronizando reloj (NTP)..."
timedatectl set-ntp true
ok "Reloj sincronizado"

info "Actualizando keyring de pacman..."
pacman -Sy --noconfirm archlinux-keyring &>/dev/null
ok "Keyring actualizado"

# ── Configuración interactiva ─────────────────────────────────────────────
echo -e "\n${Y}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${Y}║  Arch Linux — Instalación Base (UEFI / GPT)         ║${NC}"
echo -e "${Y}╚══════════════════════════════════════════════════════╝${NC}\n"

info "Discos disponibles:"
lsblk -d -o NAME,SIZE,MODEL -e 7,11
echo ""

read -rp "Disco destino (ej: /dev/sda, /dev/nvme0n1): " DISK
[[ -z "$DISK" ]] && fail "Debes especificar un disco"
[[ ! -b "$DISK" ]] && fail "Disco $DISK no encontrado"

read -rp "Hostname [archlinux]: " HOSTNAME
HOSTNAME="${HOSTNAME:-archlinux}"

read -rp "Usuario [jufedev]: " USERNAME
USERNAME="${USERNAME:-jufedev}"

read -rp "Timezone [America/Bogota]: " TIMEZONE
TIMEZONE="${TIMEZONE:-America/Bogota}"

read -rp "Locale [en_US.UTF-8]: " LOCALE
LOCALE="${LOCALE:-en_US.UTF-8}"

read -rp "Keymap [us]: " KEYMAP
KEYMAP="${KEYMAP:-us}"

if [[ "$DISK" == *"nvme"* ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

# ── Resumen y confirmación ────────────────────────────────────────────────
echo ""
info "Resumen de configuración:"
echo "  Disco:    $DISK ($PART1 = EFI, $PART2 = root)"
echo "  Hostname: $HOSTNAME"
echo "  Usuario:  $USERNAME"
echo "  Timezone: $TIMEZONE"
echo "  Locale:   $LOCALE"
echo "  Keymap:   $KEYMAP"
echo ""
echo -e "${R}ADVERTENCIA: Esto borrará TODO en ${DISK}${NC}"
read -rp "¿Continuar? (s/N): " confirm
[[ "$confirm" != "s" && "$confirm" != "S" ]] && exit 0

# ── 1. Particionado (GPT, EFI + root) ────────────────────────────────────
info "Particionando $DISK (GPT)..."
sgdisk -Z "$DISK" &>/dev/null
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:"ROOT" "$DISK"
ok "Particionado completado"

# ── 2. Formatear y montar ──────────────────────────────────────────────────
info "Formateando $PART1 como FAT32 (EFI)..."
mkfs.fat -F32 "$PART1"
ok "EFI formateada"

info "Formateando $PART2 como ext4..."
mkfs.ext4 -F "$PART2"
ok "Root formateada"

info "Montando en /mnt..."
mount "$PART2" /mnt
mkdir -p /mnt/boot/efi
mount "$PART1" /mnt/boot/efi
ok "Montado"

# ── 3. Instalar sistema base ──────────────────────────────────────────────
# Microcode del CPU: crítico en baremetal (parches de erratas/seguridad del
# fabricante). En una VM no aplica — por eso es fácil olvidarlo.
if grep -q "AuthenticAMD" /proc/cpuinfo; then
    UCODE="amd-ucode"
elif grep -q "GenuineIntel" /proc/cpuinfo; then
    UCODE="intel-ucode"
else
    UCODE=""
fi
[[ -n "$UCODE" ]] && info "Microcode detectado: $UCODE" || warn "Vendor de CPU desconocido — sin microcode"

info "Instalando sistema base con pacstrap..."
pacstrap -K /mnt \
    base linux linux-headers linux-firmware ${UCODE} \
    base-devel git vim sudo \
    networkmanager grub efibootmgr \
    mesa \
    pipewire pipewire-alsa pipewire-pulse wireplumber
ok "Sistema base instalado"

# ── 4. Generar fstab ──────────────────────────────────────────────────────
info "Generando fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generado"

# ── 5. Configuración dentro de chroot ─────────────────────────────────────
info "Configurando sistema dentro de chroot..."

arch-chroot /mnt /bin/bash <<CHROOT_SCRIPT
set -euo pipefail

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locale
sed -i 's/#${LOCALE}/${LOCALE}/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Habilitar multilib (para paquetes 32-bit si se necesitan)
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf

# Configurar pacman: colores y descargas paralelas
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

# GRUB (UEFI)
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Crear usuario
useradd -m -G wheel -s /bin/bash ${USERNAME}
echo "root:root" | chpasswd
echo "${USERNAME}:${USERNAME}" | chpasswd
chage -d 0 root
chage -d 0 ${USERNAME}
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Servicios
systemctl enable NetworkManager

# Clonar repo de configuración
cd /home/${USERNAME}
git clone ${REPO_URL} || true
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}

# Swapfile (4 GB)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
echo '/swapfile none swap defaults 0 0' >> /etc/fstab

echo "✓ Chroot configurado"
CHROOT_SCRIPT

ok "Configuración de chroot completada"

# ── 6. Finalizar ──────────────────────────────────────────────────────────
echo ""
ok "Instalación base completada"
echo ""
echo -e "${G}Próximos pasos:${NC}"
echo "  1. umount -R /mnt"
echo "  2. reboot"
echo "  3. Loguearse como ${USERNAME} (contraseña temporal: ${USERNAME})"
echo "  4. El sistema te pedirá cambiar la contraseña en el primer login"
echo "  5. Ejecutar: bash ~/archlinux-setup/scripts/postinstall.sh"
