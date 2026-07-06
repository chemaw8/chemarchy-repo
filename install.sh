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
    chemarchy-identity install >/dev/null 2>&1 && ok "identidad chemarchy" \
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
  ok "--from-calamares completo (cero descargas)"
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
