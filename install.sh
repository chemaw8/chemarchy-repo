#!/usr/bin/env bash
# chemarchy-install — one-shot idempotente: lleva una caja (nueva o existente) a chemarchy.
#   curl -fsSL https://chemaw8.github.io/chemarchy-repo/install.sh | bash
#   curl … | bash -s -- --channel rc --no-extras
#   chemarchy-install --from-calamares     (módulo shellprocess del ISO, offline, root)
#
# Doble vida: corre igual por curl|bash (sin repo git) y como módulo Calamares. Es AUTOCONTENIDO
# en los pasos 0-3 (NO sourcea libs: en el paso 0 aún no hay nada de chemarchy instalado).
# set -uo SIN -e (cada paso maneja su error; patrón de chemarchy-wizard:6 / chemarchy-update:8).
set -uo pipefail

REPO_BASE="${CHEMARCHY_REPO_BASE:-https://github.com/chemaw8/chemarchy-repo/releases/download}"
# ^ Fuente única del Server URL del one-shot. NUNCA con /x86_64 (los assets de Release son planos).
CHEMARCHY_INSTALL_PREFIX="${CHEMARCHY_INSTALL_PREFIX:-/}"   # raíz de /etc (override en tests)
ASKPASS="${SUDO_ASKPASS:-/usr/bin/ksshaskpass}"
KEYID=069CA59152A9E92A   # llave de firma del repo [chemarchy] (referencia; el keyring la importa)
KEYFPR=9019977256F9F5CDD4907C02069CA59152A9E92A   # fingerprint COMPLETO esperado del keyring (ancla de confianza)
LOGFILE="/dev/null"      # hasta log_init: evita error de redirección si log() corre antes (p.ej. die en parse_args)

# ── helpers ───────────────────────────────────────────────────────────────
sudo_a() {
  if [ "$(id -u)" = 0 ]; then "$@"; return; fi
  if [ -n "${CHEM_GRAPHICAL:-}" ] && [ -x "$ASKPASS" ]; then
    SUDO_ASKPASS="$ASKPASS" sudo -A "$@"
  else
    sudo "$@"   # sin sesión gráfica / sin ksshaskpass → pide la contraseña por la terminal
  fi
}
log_init() {
  if [ "$(id -u)" = 0 ]; then LOGFILE="/var/log/chemarchy-install.log"
  else LOGFILE="${XDG_STATE_HOME:-$HOME/.local/state}/chemarchy/install.log"; fi
  mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
  : >> "$LOGFILE" 2>/dev/null || LOGFILE=/dev/null
}
log()      { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOGFILE" 2>/dev/null || true; }
progress() { printf '\n\033[1;35m» Paso %s/6: %s\033[0m\n' "$1" "$2"; log "[$1] $2"; }
info()     { printf '  %s\n' "$*"; }
warn()     { printf '  \033[33m⚠ %s\033[0m\n' "$*"; log "WARN: $*"; }
ok()       { printf '\033[32m✓ %s\033[0m\n' "$*"; log "OK: $*"; }
die()      {
  local n="$1"; shift
  printf '\033[31m✗ Falló en el paso %s: %s\033[0m\n' "$n" "$*" >&2
  printf '  Es seguro reintentar:  curl -fsSL https://chemarchy.sh | bash\n' >&2
  printf '  Diagnóstico:           chemarchy doctor\n' >&2
  log "FAIL[$n]: $*"; exit 1
}

# ── flags ─────────────────────────────────────────────────────────────────
parse_args() {
  CHANNEL="${CHEMARCHY_CHANNEL:-stable}"
  EXTRAS=1; UNATTENDED=0; OFFLINE=0; FROM_CALAMARES=0; PERSONAL=""; OWNER=0; TARGET=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --channel)        CHANNEL="${2:-}"; shift 2 ;;
      --channel=*)      CHANNEL="${1#*=}"; shift ;;
      --no-extras)      EXTRAS=0; shift ;;
      --unattended)     UNATTENDED=1; shift ;;
      --personal)       PERSONAL="${2:-}"; shift 2 ;;
      --owner)          OWNER=1; shift ;;
      --offline)        OFFLINE=1; shift ;;
      --target)         TARGET="${2:-}"; shift 2 ;;
      --from-calamares) FROM_CALAMARES=1; shift ;;
      -h|--help)        usage; exit 0 ;;
      *)                printf '  ⚠ flag desconocido: %s\n' "$1" >&2; shift ;;
    esac
  done
  case "$CHANNEL" in stable|rc|edge) ;; *) die 0 "canal inválido '$CHANNEL' (stable|rc|edge)";; esac
  [ "$FROM_CALAMARES" = 1 ] && OFFLINE=1
}

usage() {
  cat <<'EOF'
chemarchy-install — instala chemarchy en un sistema CachyOS/Arch + KDE.
  --channel <stable|rc|edge>   canal de actualización (default: stable)
  --no-extras                  omite las apps AUR opcionales (camino crítico = pacman -S chemarchy)
  --personal <owner/repo>      activa el overlay personal tras instalar
  --owner                      atajos del dueño (sugerencia de 'chemarchy replicate')
  --offline                    no usa red (ISO / sin internet)
  --target <dir>               raíz alterna (reservado)
  --unattended                 sin confirmaciones
  --from-calamares             módulo del ISO (root, offline): identidad + keyring + servicios
EOF
}

# ── pasos (stubs; Tareas 3-5 los implementan) ──────────────────────────────
ensure_clock() {
  command -v timedatectl >/dev/null 2>&1 || return 0
  sudo_a timedatectl set-ntp true 2>/dev/null || true
  local floor=1782432000 i=0   # 2026-06-26: piso de validez de la llave del keyring
  while [ "$(date +%s)" -lt "$floor" ] && [ "$i" -lt 30 ]; do
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = yes ] && break
    sleep 1; i=$((i+1))
  done
  [ "$(date +%s)" -lt "$floor" ] && \
    warn "El reloj sigue atrasado ($(date)); la verificación de la llave puede fallar. Ajusta la hora y reintenta."
  return 0
}
step_preflight() {
  progress 0 "Pre-vuelo (reloj · red · sistema)"
  ensure_clock
  command -v pacman >/dev/null 2>&1 || die 0 "Esto requiere Arch/CachyOS (no encontré pacman)."
  if [ "$OFFLINE" != 1 ]; then
    curl -fsI --max-time 8 "$REPO_BASE/$CHANNEL/chemarchy.db" >/dev/null 2>&1 \
      || curl -fsI --max-time 8 "https://github.com" >/dev/null 2>&1 \
      || die 0 "Sin acceso a internet. Conéctate y reintenta el comando (o usa --offline en el ISO)."
  fi
  command -v plasmashell >/dev/null 2>&1 || warn "No detecté KDE Plasma; chemarchy asume KDE — continúo."
  # sesión gráfica → habilita el ASKPASS de ksshaskpass para sudo_a (si no, TTY)
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && [ -x "$ASKPASS" ] && CHEM_GRAPHICAL=1 || true
}
step_keyring() {
  progress 1 "Instalando la llave de firma (keyring · KEYID $KEYID)"
  if pacman -Qq chemarchy-keyring >/dev/null 2>&1; then info "la llave ya está presente"; return 0; fi
  local url="$REPO_BASE/$CHANNEL/chemarchy-keyring.pkg.tar.zst"
  local tmp; tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/chemarchy-keyring.pkg.tar.zst" || { rm -rf "$tmp"; die 1 "No pude descargar el keyring ($url)."; }
  # ancla de confianza: este pacman -U corre SIN firma que lo avale (es el bootstrap del trust),
  # así que el contenido se verifica contra el fingerprint fijo en el script — HTTPS solo
  # autentica a GitHub, no que el asset del release sea el keyring legítimo.
  local got; mkdir -p -m700 "$tmp/g"
  got="$(bsdtar -xOf "$tmp/chemarchy-keyring.pkg.tar.zst" usr/share/pacman/keyrings/chemarchy.gpg 2>/dev/null \
        | gpg --homedir "$tmp/g" --batch --quiet --show-keys --with-colons 2>/dev/null \
        | awk -F: '/^fpr:/{print $10; exit}')"
  [ "$got" = "$KEYFPR" ] || { rm -rf "$tmp"; die 1 "Fingerprint del keyring descargado (${got:-ilegible}) ≠ esperado ($KEYFPR) — NO lo instalo."; }
  sudo_a pacman -U --noconfirm "$tmp/chemarchy-keyring.pkg.tar.zst" || { rm -rf "$tmp"; die 1 "pacman -U del keyring falló (¿reloj atrasado?)."; }
  rm -rf "$tmp"; ok "keyring instalado"
}
step_repo() {
  progress 2 "Configurando el repo [chemarchy] (canal $CHANNEL)"
  local etc="${CHEMARCHY_INSTALL_PREFIX%/}/etc"
  local conf="$etc/pacman.d/chemarchy-channel.conf"
  local active="$etc/chemarchy-channel"
  local pacconf="$etc/pacman.conf"
  sudo_a install -Dm644 /dev/stdin "$conf" <<EOF
# repo [chemarchy] · canal $CHANNEL (escrito por chemarchy-install; espeja system/pacman/chemarchy-$CHANNEL.conf)
[chemarchy]
SigLevel = Required DatabaseRequired
Server = $REPO_BASE/$CHANNEL
EOF
  sudo_a install -Dm644 /dev/stdin "$active" <<<"$CHANNEL"
  # dedupe: installs viejos dejaron [chemarchy] inline → doble registro con el Include
  # (espejo del awk de migrations/1782960001_dedupe-chemarchy-repo.sh, con las mismas
  # líneas de rescate: el Include gestionado suele venir pegado después del bloque inline)
  if [ -f "$pacconf" ] && grep -q '^\[chemarchy\]' "$pacconf"; then
    local _t; _t="$(mktemp)"
    awk '
      /^\[/                     { skip = ($0 == "[chemarchy]") }
      /^# repo \[chemarchy\]/   { skip = 0 }
      /chemarchy-channel\.conf/ { skip = 0 }
      !skip
    ' "$pacconf" > "$_t"
    sudo_a cp "$_t" "$pacconf" || { rm -f "$_t"; die 1 "No pude limpiar el bloque [chemarchy] inline de pacman.conf."; }
    rm -f "$_t"
    info "bloque [chemarchy] inline previo removido (queda el Include)"
  fi
  local incl="Include = /etc/pacman.d/chemarchy-channel.conf"
  if [ -f "$pacconf" ] && grep -qxF "$incl" "$pacconf" 2>/dev/null; then
    info "Include ya presente en pacman.conf"
  else
    sudo_a sh -c "printf '\n# repo [chemarchy] (chemarchy-install)\n%s\n' '$incl' >> \"$pacconf\""
    ok "Include añadido a pacman.conf"
  fi
}
step_meta() {
  progress 3 "Instalando chemarchy (meta-paquete firmado)"
  sudo_a pacman -Syu --needed --noconfirm chemarchy \
    || die 3 "pacman -S chemarchy falló (revisa la firma/llave; es seguro reintentar)."
  ok "meta-paquete chemarchy instalado"
}
step_deploy() {
  progress 4 "Desplegando a tu \$HOME (restore + servicios)"
  command -v chemarchy-bootstrap >/dev/null 2>&1 || die 4 "chemarchy-bootstrap ausente tras instalar el meta."
  # restore puebla \$HOME desde /usr/share/chemarchy/skel para usuario NUEVO o EXISTENTE
  # (corre el mop-up: panel Plasma + tema default + wallpapers; ver chemarchy-bootstrap).
  chemarchy-bootstrap restore  || warn "restore con avisos (revisa arriba)."
  chemarchy-bootstrap services || warn "services con avisos."
  chemarchy-bootstrap assets   || warn "assets con avisos."
  # GPU/perf/apps/vault los hace el wizard del siguiente login (§8: GPU auto, no preguntar aquí).
}
step_extras() {
  if [ "$EXTRAS" != 1 ]; then progress 5 "Extras (omitidos: --no-extras)"; return 0; fi
  progress 5 "Extras opcionales (apps curadas vía paru) — fallos AUR = aviso"
  if ! command -v paru >/dev/null 2>&1; then
    info "paru ausente; omito extras (el camino crítico ya quedó con pacman -S chemarchy)"; return 0
  fi
  chemarchy-bootstrap packages || warn "algunos extras AUR fallaron (no es fatal)."
}
step_reconcile() {
  progress 6 "Reconciliando el escritorio (panel Plasma)"
  chemarchy-bootstrap reconcile-panel || warn "reconcile-panel con avisos."
}
run_calamares() {
  # Corre como root en el chroot del target (post-unpackfs). Sin $HOME, sin red, sin restore.
  log "modo --from-calamares: identidad + keyring-trust + servicios de sistema (offline)"
  printf '\n\033[1;35m» chemarchy: personalizando el sistema (offline)\033[0m\n'
  # 1) identidad de distro (os-release/lsb): que diga Chemarchy, no CachyOS. Idempotente.
  if command -v chemarchy-identity >/dev/null 2>&1; then
    chemarchy-identity install >>"$LOGFILE" 2>&1 && ok "identidad chemarchy" \
      || info "identidad: se reintenta tras el primer login"
  fi
  # 2) INICIALIZAR + poblar el keyring de pacman en el target (r9, E2E 06-jul). El airootfs NO trae
  #    /etc/pacman.d/gnupg (en el live es un tmpfs → unpackfs no lo copia), así que el target arrancaba
  #    SIN keyring → `pacman -Syu` fallaba ("clave cachyos 882DCFE… desconocida / ¿pacman-key --init?").
  #    Los .gpg fuente (archlinux/cachyos/chemarchy) SÍ están en /usr/share/pacman/keyrings/ vía unpackfs,
  #    así que --populate es OFFLINE (cero descargas). --init genera el master key + trustdb del target.
  if command -v pacman-key >/dev/null 2>&1; then
    pacman-key --init >/dev/null 2>&1 && ok "keyring inicializado" \
      || info "keyring: --init falló (se reintenta tras el primer login vía chemarchy-update)"
    pacman-key --populate archlinux cachyos chemarchy >/dev/null 2>&1 \
      && ok "keyring poblado (archlinux + cachyos + chemarchy)" || info "keyring: --populate parcial"
  fi
  # 3) servicios de SISTEMA (no de usuario): se habilitan en el target, arrancan al primer boot
  local s
  for s in NetworkManager bluetooth sddm plasma-login-manager; do
    systemctl enable "$s" >/dev/null 2>&1 && ok "enable $s" || true
  done
  calamares_canal
  calamares_sin_live
  # 5) Limine: la ISO excluye el desvío de limine-mkinitcpio-hook (rompía su build) → repónerlo del paquete en caché.
  #    Si no está en caché, lo repone el primer chemarchy update justo después del -Syu (regenera Limine).
  if command -v chemarchy-limine-hook >/dev/null 2>&1; then
    chemarchy-limine-hook reparar --sin-red >/dev/null 2>&1 && ok "Limine: kernels nuevos llegarán al menú" \
      || info "Limine: el desvío de kernels se repone en el primer chemarchy update"
  fi
  calamares_marca_arranque
  ok "--from-calamares completo (cero descargas)"
}
# 4) Canal de actualización horneado en el ISO (iso/build.sh → /usr/share/chemarchy/iso-channel). Sin esto el
#    target no tiene [chemarchy] en pacman.conf y jamás recibe updates (hierro nuevo, 2026-10-27). Offline: el
#    conf viene en el paquete. CHEMARCHY_INSTALL_ROOT es gancho de prueba (prefijo del target).
calamares_canal() {
  local R="${CHEMARCHY_INSTALL_ROOT:-}" ch src
  ch="$(cat "$R/usr/share/chemarchy/iso-channel" 2>/dev/null || echo stable)"
  case "$ch" in stable|rc|edge) ;; *) ch=stable ;; esac
  src="$R/usr/share/chemarchy/pacman/chemarchy-$ch.conf"
  [ -f "$src" ] || { info "canal: falta $src (se configura con chemarchy-channel-set tras el primer login)"; return 0; }
  install -Dm644 "$src" "$R/etc/pacman.d/chemarchy-channel.conf"
  printf '%s\n' "$ch" > "$R/etc/chemarchy-channel"
  local incl="Include = /etc/pacman.d/chemarchy-channel.conf"
  grep -qxF "$incl" "$R/etc/pacman.conf" 2>/dev/null \
    || printf '\n# repo [chemarchy] (gestionado por chemarchy-channel-set)\n%s\n' "$incl" >> "$R/etc/pacman.conf"
  ok "canal $ch configurado"
}
# 5) Lo del live que no debe quedar en el instalado (hierro nuevo, 2026-10-27):
#    - sshd del live con root+contraseña (10-archiso.conf) y habilitado;
#    - servicios del live/VM, y zfs sin raíz zfs: livecd-alsa-unmuter y zfs-import-cache piden
#      systemd-udev-settle (25 s con NVIDIA) y empujaban drm-module-load.target del awaiter de CachyOS más allá
#      de sus 30 s → pantalla azul «Failed to load your GPU driver(s)»;
#    - systemd-time-wait-sync: falla a los 30 s en cada arranque y nada lo necesita en escritorio.
calamares_sin_live() {
  local R="${CHEMARCHY_INSTALL_ROOT:-}" u quitar=() raiz
  rm -f "$R/etc/ssh/sshd_config.d/10-archiso.conf" && ok "sin 10-archiso.conf (root/contraseña por SSH)"
  quitar=(sshd livecd-talk livecd-alsa-unmuter hv_fcopy_daemon hv_kvp_daemon hv_vss_daemon vmware-vmblock-fuse
          vboxservice vmtoolsd systemd-time-wait-sync)
  raiz="$(findmnt -no FSTYPE / 2>/dev/null)"
  [ "$raiz" = zfs ] || quitar+=(zfs-import-cache zfs-import-scan zfs-mount zfs-import.target zfs.target zfs-zed)
  for u in "${quitar[@]}"; do systemctl disable "$u" >/dev/null 2>&1 || true; done
  ok "servicios del live/VM deshabilitados (${#quitar[@]})"
}
# 6) Marca de ARRANQUE y LOGIN en el destino (spec 019 V1; ISO E2E 2026-11-15/16: la frase LUKS salió con el logo de
#    Arch y Plasma Login con el fondo genérico de KDE). Causas: (a) nada activaba Plymouth de forma verificable aquí:
#    chemarchy-identity lo intenta con sudo + `plymouth-set-default-theme -R` y, si el rebuild falla, REGRESA la
#    selección al tema anterior; su salida iba a /dev/null → el destino quedaba con el default (bgrt/spinner = logo de
#    Arch). (b) El fondo de Plasma Login solo lo pone `chemarchy-bootstrap restore` (usuario + sudo gráfico tras el
#    primer login), nunca el instalador. Aquí, como root en el chroot y sin sudo: tema en plymouthd.conf, gancho
#    plymouth en el initramfs, initramfs regenerado (limine-update → también las imágenes de /boot/<machine-id>/) y
#    fondo de login instalado. Respeta las guardas de marca (spec 017 B). CHEMARCHY_INSTALL_ROOT = prefijo de pruebas.
calamares_marca_arranque() {
  local R="${CHEMARCHY_INSTALL_ROOT:-}" ply=chemarchy-eclipse M actual conf cambio=0
  M="$(command -v chemarchy-marca 2>/dev/null || true)"
  export CHEMARCHY_MARCA_DIR="${CHEMARCHY_MARCA_DIR:-$R/var/lib/chemarchy/marca}"
  marca_ok() { if [ -n "$M" ]; then "$M" "$@"; else return 1; fi; }   # sin ayudante no se escribe
  # ── Plymouth ──
  conf="$R/etc/plymouth/plymouthd.conf"
  if [ -d "$R/usr/share/plymouth/themes/$ply" ]; then
    actual="$(sed -n 's/^[[:space:]]*Theme[[:space:]]*=[[:space:]]*//p' "$conf" 2>/dev/null | tail -1)"
    [ -n "$actual" ] || actual="$(sed -n 's/^[[:space:]]*Theme[[:space:]]*=[[:space:]]*//p' "$R/usr/share/plymouth/plymouthd.defaults" 2>/dev/null | tail -1)"
    if [ "$actual" = "$ply" ] && grep -qE "^[[:space:]]*Theme[[:space:]]*=[[:space:]]*$ply[[:space:]]*\$" "$conf" 2>/dev/null; then
      info "Plymouth: $ply ya estaba elegido"
    elif marca_ok plymouth "$actual"; then
      mkdir -p "${conf%/*}"
      if grep -qE '^[[:space:]]*Theme[[:space:]]*=' "$conf" 2>/dev/null; then
        sed -i -E "s|^[[:space:]]*Theme[[:space:]]*=.*|Theme=$ply|" "$conf"
      elif grep -qx '\[Daemon\]' "$conf" 2>/dev/null; then
        sed -i "/^\[Daemon\]\$/a Theme=$ply" "$conf"
      else
        printf '[Daemon]\nTheme=%s\n' "$ply" >> "$conf"
      fi
      marca_ok registrar plymouth "$ply" || true
      ok "Plymouth: tema $ply (antes: ${actual:-ninguno})"
    else info "Plymouth: «$actual» no es un default, no lo cambio"; fi
    # el gancho plymouth (antes del cifrado: si no, la frase LUKS se pide en texto)
    install -Dm644 /dev/stdin "$R/etc/mkinitcpio.conf.d/20-chemarchy-plymouth.conf" <<'EOF'
# chemarchy (calamares_marca_arranque): Plymouth en el initramfs, antes de sd-encrypt/encrypt, para que el splash
# y la petición de la frase LUKS salgan con el tema. No-op si el HOOKS ya lo trae.
if [[ " ${HOOKS[*]} " != *" plymouth "* ]]; then
  _h=()
  for _x in "${HOOKS[@]}"; do _h+=("$_x"); [[ $_x = systemd || $_x = udev ]] && _h+=(plymouth); done
  [[ " ${_h[*]} " == *" plymouth "* ]] || _h+=(plymouth)
  HOOKS=("${_h[@]}"); unset _h _x
fi
EOF
    rm -f "$R/var/lib/chemarchy/marca/plymouth-pendiente"
    cambio=1
  else info "Plymouth: el tema $ply no está en el destino (¿falta chemarchy-themes?)"; fi
  # regenerar el initramfs DEL DESTINO (corre dentro del chroot de Calamares). Hay DOS juegos y hacen falta los dos
  # (ISO E2E de Corona, 2026-11-16): mkinitcpio -P rehace /boot/initramfs-*.img, que es el que usa la entrada
  # «/chemarchy» de Limine (la primera, la de arranque por defecto); limine-update rehace /boot/<machine-id>/…
  # Con solo limine-update, la entrada por defecto arrancaba con el initramfs viejo y el logo de Arch.
  if [ "$cambio" = 1 ]; then
    local falta=""
    if command -v mkinitcpio >/dev/null 2>&1 && mkinitcpio -P >>"$LOGFILE" 2>&1; then ok "initramfs regenerado (mkinitcpio -P)"
    else falta="mkinitcpio -P"; fi
    if command -v limine-update >/dev/null 2>&1; then
      if limine-update >>"$LOGFILE" 2>&1; then ok "imágenes de Limine regeneradas (limine-update)"; else falta="${falta:+$falta y }limine-update"; fi
    fi
    # cada una cuenta: mkinitcpio -P es el de la entrada por defecto; si falla, se avisa aunque limine-update pase
    if [ -n "$falta" ]; then warn "no pude regenerar ($falta): el splash sale en el siguiente update del kernel"
      mkdir -p "$R/var/lib/chemarchy/marca" && : > "$R/var/lib/chemarchy/marca/plymouth-pendiente"; fi
  fi
  # ── Plasma Login: fondo Eclipse ──
  local src="$R/usr/share/chemarchy/system/plasmalogin/wallpapers/chemarchy-eclipse.jpg"
  local dst=/var/lib/plasmalogin/wallpapers/chemarchy-eclipse.jpg pl="$R/etc/plasmalogin.conf"
  local grupo='[Greeter][Wallpaper][org.kde.image][General]'
  if [ ! -f "$src" ]; then info "login: falta el fondo en $src"; return 0; fi
  actual="$(awk -v g="$grupo" '$0==g{s=1;next} /^\[/{s=0} s && /^Image=/{sub(/^Image=/,"");v=$0} END{print v}' "$pl" 2>/dev/null)"
  if marca_ok plasmalogin "$actual" && marca_ok archivo plasmalogin-fondo "$R$dst"; then
    install -Dm644 "$src" "$R$dst" && marca_ok registrar plasmalogin-fondo "$R$dst" || true
    [ -f "$pl" ] || : > "$pl"
    awk -v g="$grupo" -v v="Image=file://$dst" '
      $0==g {print; print v; s=1; hecho=1; next}
      /^\[/ {s=0}
      s && /^Image=/ {next}
      {print}
      END {if (!hecho) {print ""; print g; print v}}' "$pl" > "$pl.tmp" && mv -f "$pl.tmp" "$pl"
    chmod 644 "$pl"
    marca_ok registrar plasmalogin "file://$dst" || true
    ok "Plasma Login: fondo Eclipse"
  else info "login: el fondo de Plasma Login es tuyo, no lo cambio"; fi
}
handoff() {
  ok "Listo. Cierra sesión y vuelve a entrar — un asistente (chemarchy-wizard) te ayudará a terminar."
  info "Después: 'chtheme pick' (tema) · 'chemarchy apps' · 'chemarchy update' · 'chemarchy doctor' (si algo falla)."
}

main() {
  parse_args "$@"
  log_init
  if [ "$FROM_CALAMARES" = 1 ]; then run_calamares; exit $?; fi
  step_preflight
  step_keyring
  step_repo
  step_meta
  if [ -n "$PERSONAL" ] && command -v chemarchy-channel-set >/dev/null 2>&1; then
    chemarchy-channel-set --personal on "$PERSONAL" || warn "no pude activar el overlay personal ($PERSONAL)."
  fi
  step_deploy
  step_extras
  step_reconcile
  handoff
  # forma if (no `&& info`): que main retorne 0 en instalación exitosa aunque OWNER=0.
  if [ "$OWNER" = 1 ]; then info "Dueño: 'chemarchy replicate' monta overlay + restic + vault."; fi
}

# seam de test: con CHEMARCHY_INSTALL_SOURCED=1 se puede `source` sin ejecutar main.
[ "${CHEMARCHY_INSTALL_SOURCED:-0}" = 1 ] || main "$@"
