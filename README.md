# chemarchy-repo

Canal **pacman firmado** de [chemarchy](https://github.com/chemaw8/chemarchy) — el repo `[chemarchy]`.
Aquí viven solo los **paquetes y la base de datos firmados** (assets de Release); el fuente es privado.

Firmados con la llave dedicada del repo:

```
KEYID  069CA59152A9E92A
FPR    9019 9772 56F9 F5CD D490  7C02 069C A591 52A9 E92A
UID    Chemarchy Repository Signing Key <chemarchy@chemaw8.github.io>
```


![chemarchy](https://github.com/chemaw8/chemarchy-repo/raw/main/assets/chemarchy-neon-lofi.png)

Una curaduría opinada de KDE Plasma 6 (Wayland) sobre CachyOS/Arch: shell propio en Quickshell, temas que se
siguen entre apps (siete temas; el de fábrica es **Eclipse**, la cara de chemarchy: negro rojizo, corona carmesí),
tiling, dock, atajos y un asistente de primer arranque. **Instalar es un comando.**

## Instalar — ya tienes CachyOS/Arch + KDE Plasma (1 comando)

```bash
curl -fsSL https://github.com/chemaw8/chemarchy-repo/raw/main/install.sh | bash
```

Eso sincroniza el reloj, instala la llave (verificando su fingerprint), añade el repo firmado
`[chemarchy]`, instala el meta-paquete y despliega la config a tu `$HOME`. Al **siguiente login**
corre un asistente que termina de personalizar.

¿Prefieres inspeccionar antes de correr? (recomendado para cualquier `curl|bash`):

```bash
curl -fsSL https://github.com/chemaw8/chemarchy-repo/raw/main/install.sh -o install.sh
less install.sh        # léelo
bash install.sh        # córrelo
```

Con opciones: `… | bash -s -- --channel rc --no-extras`
· o el canal edge: `curl -fsSL … | bash -s -- --channel edge`.

## Computadora nueva o vacía (ISO)

Todavía **no hay una ISO publicada** con su checksum, así que por ahora el único camino es el de arriba: instala
CachyOS con KDE Plasma (su instalador oficial) y corre el comando de instalación. Cuando haya una ISO publicada, aquí
irán el enlace de descarga, su `.sha256` y los pasos para grabarla en una USB.

Si ya arrancaste una ISO de chemarchy (sesión live), el instalador es el icono **Instalar chemarchy** del escritorio;
la guía `~/Documentos/CHEMARCHY-empieza-aqui.md` explica qué esperar después.

## Después de instalar

- `chtheme pick` — cambia de tema · `chemarchy apps` — bundles de apps · `chemarchy update` — actualiza
- `chemarchy-channel-set stable|rc|edge` — cambia de canal · `chemarchy doctor` — diagnostica/repara
- `Super+/` — cheatsheet completo · `chemarchy help` — todos los comandos
- Re-correr el asistente: `chemarchy-wizard --force`

Si algo se atora en cualquier punto, el mensaje te dice el comando exacto a correr (`chemarchy doctor`,
o reintentar `curl … | bash`). El objetivo: instalarlo **sin ayuda humana**.

## sudo sin contraseña (instalaciones desde una ISO)

Al instalar desde una ISO de chemarchy, el grupo `wheel` (tu usuario) queda con `sudo` **sin contraseña**, igual que
en la sesión live (`/etc/sudoers.d/g_wheel`). Es una decisión del proyecto: cómodo, pero cualquier
programa que corra con tu usuario puede ser root. El comando de instalación (`install.sh`) no toca tu sudo.

Para quitarlo y que `sudo` vuelva a pedir contraseña:

```bash
sudo passwd "$USER"                       # 1. si aún no tienes contraseña (o no la recuerdas): fíjala
sudo visudo -f /etc/sudoers.d/g_wheel     # 2. deja la línea así:  %wheel ALL=(ALL:ALL) ALL
sudo visudo -c                            # 3. valida toda la configuración de sudo
sudo -k; sudo true                        # 4. debe pedirte la contraseña del paso 1
```

No borres `g_wheel`: suele ser la única regla de `wheel` y sin ella te quedas sin sudo. Si el paso 3
marca un error, repite el paso 2 antes de cerrar la terminal.

## IA

El sidebar de IA (`Meta+Shift+I`) y `chemarchy ai` usan Claude con **tu cuenta de Claude Code** (hace falta
`claude` con sesión iniciada; no se configura API key). **No es local:** lo que le mandas, incluidas
capturas y texto de OCR, viaja a Anthropic. `chemarchy diagnose` oculta datos sensibles antes de enviar
(`chemarchy-diagnose --evidence` muestra qué saldría).

---

> Repo de distribución; canales `stable`/`rc`/`edge` = tags de Release. Cada paquete y la db se
> verifican con `SigLevel=Required` contra la llave de arriba. Personalización sin forkear:
> `cp /usr/share/chemarchy/user.conf.example ~/.config/chemarchy/user.conf`.
