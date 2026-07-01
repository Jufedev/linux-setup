#!/usr/bin/env bash
# ============================================================================
# plasma6macos — módulo compartido del look macOS para KDE Plasma 6
#
# NO se ejecuta directo: se *sourcea* desde <distro>/scripts/postinstall.sh.
# Contiene las funciones distro-agnósticas que aplican el pack plasma6macos
# (MacSequoia + MacTahoe + Kvantum + plasmoides + KWin + layout + wallpaper).
#
# Contrato del caller — definir ANTES de sourcear:
#   Funciones : info, ok, warn, step, run_module
#   Variables : MACOS_PKG_INSTALL  nombre de la función que instala paquetes
#                                  (fedora: dnf_install / arch: pac_install)
#               VENDOR_DIR         dir con los zips del pack (shared/vendor/plasma6macos)
#               KDE_CONFIGS_DIR    dir con las configs KDE (shared/configs/kde)
#               LOG_FILE           log persistente del setup
#               QDBUS              binario qdbus resuelto (puede ser vacío)
# ============================================================================

# Guard del contrato: fallar acá con un mensaje claro es mejor que un
# "unbound variable" críptico a mitad de un módulo (los scripts usan set -u).
for _p6m_req in MACOS_PKG_INSTALL VENDOR_DIR KDE_CONFIGS_DIR LOG_FILE QDBUS; do
    if [[ -z "${!_p6m_req+x}" ]]; then
        echo "plasma6macos.sh: falta definir \$${_p6m_req} antes de sourcear el módulo" >&2
        # 'return' aplica cuando el archivo se sourcea (el caso normal); el 'exit'
        # solo corre si alguien lo ejecuta directo, donde 'return' falla.
        # shellcheck disable=SC2317
        return 1 2>/dev/null || exit 1
    fi
done
unset _p6m_req

# ── plasma6macos pack (vendorizado) ──────────────────────────────────────────
# El look del video ES el pack plasma6macos COMPLETO (autor: Lsteam). NO tiene
# versionado en la KDE Store → vive vendorizado en shared/vendor/plasma6macos/
# (ver su ATTRIBUTION.md). El tema es MacSequoia + iconos MacTahoe (vinceliuice).
# Reemplazó por completo al stack WhiteSur. MacSequoia-Light es el default.
readonly MACOS_LNF="com.github.vinceliuice.MacSequoia-Light"

# Extrae un zip vendorizado del pack a un tmp dir. Deja la ruta en $_VENDOR_TMP.
# Devuelve 1 (sin abortar) si el asset no está o falla la extracción.
_VENDOR_TMP=""
_extract_vendor() {
    local zip_name="$1"
    local zip_path="${VENDOR_DIR}/${zip_name}"
    _VENDOR_TMP=""
    if [[ ! -f "$zip_path" ]]; then
        warn "Asset vendorizado no encontrado: $zip_path — salteando"
        return 1
    fi
    command -v unzip &>/dev/null || "$MACOS_PKG_INSTALL" unzip
    _VENDOR_TMP="$(mktemp -d)"
    if ! unzip -q -o "$zip_path" -d "$_VENDOR_TMP" >>"$LOG_FILE" 2>&1; then
        warn "Falló la extracción de $zip_name"
        rm -rf "$_VENDOR_TMP"; _VENDOR_TMP=""
        return 1
    fi
    return 0
}

# ── plasma6macos assets — iconos + cursores ──────────────────────────────────
# Iconos MacTahoe (lo que el look-and-feel MacSequoia referencia) + cursores
# WhiteSur-cursors (idem). Van a ~/.local/share/icons/. La SELECCIÓN del tema la
# hace apply_macos_layout vía el look-and-feel.
install_macos_icons_cursors() {
    step "plasma6macos — iconos (MacTahoe) + cursores (WhiteSur)"
    local dest="${HOME}/.local/share/icons"
    mkdir -p "$dest"
    if _extract_vendor plasma6macos-icons.zip; then
        cp -rf "$_VENDOR_TMP"/. "$dest/" || warn "no se pudieron copiar todos los iconos"
        rm -rf "$_VENDOR_TMP"
        info "Iconos MacTahoe instalados"
    fi
    if _extract_vendor plasma6macos-cursors.zip; then
        cp -rf "$_VENDOR_TMP"/. "$dest/" || warn "no se pudieron copiar todos los cursores"
        rm -rf "$_VENDOR_TMP"
        info "Cursores WhiteSur instalados"
    fi
    command -v gtk-update-icon-cache &>/dev/null \
        && gtk-update-icon-cache -q "$dest/MacTahoe-light" 2>/dev/null || true
    ok "Iconos + cursores instalados"
}

# ── plasma6macos assets — fuentes ────────────────────────────────────────────
# Fuentes del pack (Adwaita Sans/Mono). Van a ~/.local/share/fonts/ + fc-cache.
install_macos_fonts() {
    step "plasma6macos — fuentes del pack"
    _extract_vendor plasma6macos-fonts.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN
    local dest="${HOME}/.local/share/fonts"
    mkdir -p "$dest"
    cp -rf "$src"/. "$dest/"
    command -v fc-cache &>/dev/null && fc-cache -f "$dest" >>"$LOG_FILE" 2>&1 || true
    ok "Fuentes del pack instaladas"
}

# ── plasma6macos assets — tema GTK ───────────────────────────────────────────
# Tema GTK MacTahoe (apps GTK3/GTK4). Va a ~/.local/share/themes/. La selección
# (GtkTheme) la hace apply_macos_layout.
install_macos_gtk() {
    step "plasma6macos — tema GTK (MacTahoe)"
    _extract_vendor plasma6macos-gtk-theme.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN
    local dest="${HOME}/.local/share/themes"
    mkdir -p "$dest"
    cp -rf "$src"/. "$dest/"
    ok "Tema GTK MacTahoe instalado"
}

# ── plasma6macos assets — Kvantum ────────────────────────────────────────────
# Estilo de widgets Qt: Kvantum + tema MacSequoia. El pack pone widgetStyle=Darkly
# en su look-and-feel, pero Darkly NO se distribuye en el pack; usamos Kvantum
# MacSequoia (que sí viene y da los menús translúcidos del video). apply_macos_layout
# fuerza widgetStyle=kvantum DESPUÉS de aplicar el look-and-feel.
install_macos_kvantum() {
    step "plasma6macos — Kvantum (MacSequoia widget style)"
    command -v kvantummanager &>/dev/null || "$MACOS_PKG_INSTALL" kvantum
    _extract_vendor plasma6macos-kvantum-config.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN
    local dest="${HOME}/.config/Kvantum"
    mkdir -p "$dest"
    cp -rf "$src"/. "$dest/"
    ok "Kvantum MacSequoia instalado"
}

# Plasmoides custom: Tahoe Launcher (botón de apps), KdeControlStation, kMenu (),
# weather y title-bar. Se copian a ~/.local/share/plasma/plasmoids/ (idempotente).
install_macos_plasmoids() {
    step "plasma6macos — plasmoides (Launchpad, Control Center, , weather)"
    _extract_vendor plasma6macos-plasmoids.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local dest="${HOME}/.local/share/plasma/plasmoids"
    mkdir -p "$dest"
    if [[ -d "$src/plasmoids" ]]; then
        cp -rf "$src/plasmoids/." "$dest/"
        ok "Plasmoides instalados en $dest"
    else
        warn "El archivo no contiene plasmoids/ — nada que copiar"
    fi
}

# Tema MacSequoia: desktoptheme (estilo Plasma) + Aurorae (deco) + color-schemes +
# look-and-feel + wallpapers. Va a ~/.local/share/ (idempotente).
install_macos_plasma_theme() {
    step "plasma6macos — tema MacSequoia (Plasma + Aurorae + color schemes)"
    _extract_vendor plasma6macos-plasma-theme.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local share="${HOME}/.local/share"
    mkdir -p "$share/plasma/desktoptheme" "$share/plasma/look-and-feel" \
             "$share/aurorae/themes" "$share/color-schemes" "$share/wallpapers"
    [[ -d "$src/plasma/desktoptheme"  ]] && cp -rf "$src/plasma/desktoptheme/."  "$share/plasma/desktoptheme/"
    [[ -d "$src/plasma/look-and-feel" ]] && cp -rf "$src/plasma/look-and-feel/." "$share/plasma/look-and-feel/"
    [[ -d "$src/aurorae/themes"       ]] && cp -rf "$src/aurorae/themes/."       "$share/aurorae/themes/"
    [[ -d "$src/color-schemes"        ]] && cp -rf "$src/color-schemes/."        "$share/color-schemes/"
    [[ -d "$src/wallpapers"           ]] && cp -rf "$src/wallpapers/."           "$share/wallpapers/"
    ok "Tema MacSequoia instalado"
}

# Efectos KWin (blur, kinetic), scripts y tabbox + el plugin de wallpaper con blur.
# Quedan disponibles; se activan al recargar KWin / volver a entrar.
install_macos_kwin_effects() {
    step "plasma6macos — efectos KWin (blur, kinetic) + tabbox"
    _extract_vendor plasma6macos-kwin-effect.zip || return 0
    local src="$_VENDOR_TMP"
    trap 'rm -rf "${src:-}" 2>/dev/null || true' RETURN

    local share="${HOME}/.local/share"
    mkdir -p "$share/kwin/effects" "$share/kwin/scripts" "$share/kwin/tabbox" "$share/plasma/wallpapers"
    [[ -d "$src/kwin/effects" ]] && cp -rf "$src/kwin/effects/." "$share/kwin/effects/"
    [[ -d "$src/kwin/scripts" ]] && cp -rf "$src/kwin/scripts/." "$share/kwin/scripts/"
    [[ -d "$src/kwin/tabbox"  ]] && cp -rf "$src/kwin/tabbox/."  "$share/kwin/tabbox/"
    [[ -d "$src/wallpapers"   ]] && cp -rf "$src/wallpapers/."   "$share/plasma/wallpapers/"
    [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true
    ok "Efectos KWin instalados (se aplican al recargar KWin / re-login)"
}

# Aplica el layout EXACTO del pack (su appletsrc, variante neon = la más cercana a
# upstream, con dev.xarbit.appgrid → TahoeLauncher) + el look-and-feel MacSequoia.
# Reemplaza al panel-layout.js procedural (que queda como fallback vía --desktop).
# Hace backup del layout actual una sola vez antes de pisarlo.
apply_macos_layout() {
    step "plasma6macos — layout de paneles (barra + dock) + look MacSequoia"

    local appletsrc="${KDE_CONFIGS_DIR}/plasma6macos/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ ! -f "$appletsrc" ]]; then
        warn "Layout no encontrado: $appletsrc — salteando"
        return 0
    fi

    local target="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"
    mkdir -p "${HOME}/.config"
    if [[ -f "$target" && ! -f "${target}.pre-macos.bak" ]]; then
        cp "$target" "${target}.pre-macos.bak"
        info "Backup del layout previo → ${target}.pre-macos.bak"
    fi
    cp "$appletsrc" "$target"
    info "Layout plasma6macos aplicado"

    # Look-and-feel MacSequoia (estilo Plasma + esquema de color + iconos MacTahoe +
    # Aurorae + cursor en un paso).
    if command -v plasma-apply-lookandfeel &>/dev/null; then
        plasma-apply-lookandfeel -a "$MACOS_LNF" 2>&1 | tee -a "$LOG_FILE" \
            || warn "plasma-apply-lookandfeel devolvió non-zero (normal sin sesión gráfica)"
    fi

    # Overrides DESPUÉS del look-and-feel (el LnF setea widgetStyle=Darkly, que no
    # distribuimos): forzamos Kvantum MacSequoia + tema GTK MacTahoe.
    if command -v kwriteconfig6 &>/dev/null; then
        kwriteconfig6 --file kdeglobals --group KDE     --key widgetStyle kvantum
        kwriteconfig6 --file kdeglobals --group General --key GtkTheme MacTahoe-Light

        # macOS: ocultar la barra de título de las ventanas maximizadas (los botones
        # y el nombre ya viven en la barra superior fija vía application-title-bar).
        # BorderlessMaximizedWindows es nativo de KWin; el script 'truely-maximized'
        # (del pack) hace lo mismo de forma más completa — lo activamos también.
        kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
        kwriteconfig6 --file kwinrc --group Plugins --key truely-maximizedEnabled true
    fi
    command -v kvantummanager &>/dev/null \
        && kvantummanager --set MacSequoia 2>&1 | tee -a "$LOG_FILE" || true

    # Wallpaper MacSequoia (instalado por install_macos_plasma_theme).
    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        plasma-apply-wallpaperimage "${HOME}/.local/share/wallpapers/MacSequoia-Light" 2>&1 \
            | tee -a "$LOG_FILE" || warn "wallpaper apply non-zero (normal sin sesión gráfica)"
    fi
    [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin /KWin reconfigure 2>/dev/null || true

    # Recargar plasmashell para tomar el nuevo appletsrc. Solo con sesión gráfica;
    # headless avisa que hay que volver a entrar.
    if [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && command -v kquitapp6 &>/dev/null; then
        info "Reiniciando plasmashell para cargar el layout..."
        kquitapp6 plasmashell 2>/dev/null || true
        sleep 1
        if command -v kstart &>/dev/null; then
            (kstart plasmashell >/dev/null 2>&1 &)
        else
            (setsid plasmashell >/dev/null 2>&1 &)
        fi

        # Esperar a que plasmashell vuelva y ajustar la geometría de los paneles
        # (dock flotante/centrado + barra superior más fina) vía scripting API —
        # esas props no se setean confiablemente desde el appletsrc estático.
        local geo="${KDE_CONFIGS_DIR}/plasma6macos/panel-geometry.js"
        if [[ -n "$QDBUS" && -f "$geo" ]]; then
            local _i
            for _i in $(seq 1 20); do
                "$QDBUS" org.kde.plasmashell /PlasmaShell \
                    org.kde.PlasmaShell.evaluateScript "0" &>/dev/null && break
                sleep 1
            done
            "$QDBUS" org.kde.plasmashell /PlasmaShell \
                org.kde.PlasmaShell.evaluateScript "$(cat "$geo")" 2>&1 \
                | tee -a "$LOG_FILE" || warn "no se pudo ajustar la geometría de los paneles"
        fi
        ok "Layout aplicado — plasmashell reiniciado"
    else
        warn "Sin sesión gráfica — cerrá sesión y volvé a entrar (después: bash postinstall.sh --macos-look para la geometría)"
    fi
}

# Aplica el wallpaper MacSequoia (lo instala install_macos_plasma_theme). Existe
# como módulo suelto para el flag --wallpapers (mismo flag en ambas distros).
set_macos_wallpaper() {
    step "Wallpaper — MacSequoia"
    local wp="${HOME}/.local/share/wallpapers/MacSequoia-Light"
    [[ -d "$wp" ]] || install_macos_plasma_theme
    if command -v plasma-apply-wallpaperimage &>/dev/null; then
        plasma-apply-wallpaperimage "$wp" 2>&1 | tee -a "$LOG_FILE" \
            || warn "wallpaper apply non-zero (normal sin sesión gráfica)"
        ok "Wallpaper MacSequoia aplicado"
    else
        warn "plasma-apply-wallpaperimage no disponible — seteá el wallpaper a mano"
    fi
}

# Umbrella del look macOS del video (pack plasma6macos COMPLETO). Primero los
# assets (iconos/fuentes/gtk/kvantum/plasmoides/tema/kwin), después la config
# (apply_macos_layout: look-and-feel + overrides + wallpaper + layout). Cada
# sub-paso corre aislado vía run_module para que un fallo no tumbe al resto.
install_macos_look() {
    run_module "Iconos + cursores (MacTahoe)" install_macos_icons_cursors
    run_module "Fuentes del pack"             install_macos_fonts
    run_module "Tema GTK (MacTahoe)"          install_macos_gtk
    run_module "Kvantum (MacSequoia)"         install_macos_kvantum
    run_module "Plasmoides"                   install_macos_plasmoids
    run_module "Tema MacSequoia (Plasma)"     install_macos_plasma_theme
    run_module "Efectos KWin"                 install_macos_kwin_effects
    run_module "Layout + look (config)"       apply_macos_layout
}

# El "tema" ES el pack plasma6macos completo (MacSequoia). Reemplazó al stack
# WhiteSur. --theme y --macos-look hacen lo mismo (alias, mismo flag en ambas distros).
install_theme() {
    install_macos_look
}
