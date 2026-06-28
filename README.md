# chemarchy-repo

Canal **pacman firmado** de [chemarchy](https://github.com/chemaw8/chemarchy) — el repo `[chemarchy]`.
Aquí viven solo los **paquetes y la base de datos firmados** (assets de Release); el fuente es privado.

Arquitectura `x86_64` · paquetes `any`. Firmados con la llave dedicada del repo:

```
KEYID  069CA59152A9E92A
FPR    9019 9772 56F9 F5CD D490  7C02 069C A591 52A9 E92A
UID    Chemarchy Repository Signing Key <chemarchy@chemaw8.github.io>
```

## Añadir el repo

1. **Confía en la llave + instala el keyring** (ancla de confianza):
   ```bash
   curl -LO https://github.com/chemaw8/chemarchy-repo/releases/download/edge/chemarchy-keyring-20260626-1-any.pkg.tar.zst
   sudo pacman -U chemarchy-keyring-20260626-1-any.pkg.tar.zst   # importa la pubkey + pacman-key --populate chemarchy
   ```

2. **Añade el repo a `/etc/pacman.conf`** (después de core/extra/multilib) reemplazando `<canal>` por `stable`, `rc`, o `edge`:
   ```ini
   [chemarchy]
   SigLevel = Required DatabaseRequired
   Server = https://github.com/chemaw8/chemarchy-repo/releases/download/<canal>/x86_64
   ```
   > En el primer install hazlo a mano: `chemarchy-channel-set` aún no existe (viene con el meta).
   > Una vez instalado, para cambiar de canal: `chemarchy-channel-set <stable|rc|edge>`.

3. **Sincroniza e instala**: `sudo pacman -Syyuu && sudo pacman -S chemarchy`

4. **Instala el resto (AUR + servicios)** — el glass blur, los temas Catppuccin y spicetify son AUR:
   ```bash
   chemarchy-bootstrap all
   ```

Listo: `Super+/` abre el cheatsheet · `theme pick` cambia de tema · `chemarchy-update` actualiza.

### ¿Quién eres?

- **Otra persona** (sin invitación) → es justo lo de arriba (pasos 1-4). El distro completo, público.
- **Colaborador invitado** → además: `gh auth login` · `chemarchy-channel-set --personal on <owner/repo>` · `chemarchy-update` (baja la capa personal del repo privado al que te invitaron).
- **El dueño** → setup completo con `chemarchy replicate` (overlay + secretos restic + vault).

> Arquitectura `x86_64`. El canal (`stable`, `rc`, o `edge`) es el tag del release en GitHub.
> La db y cada paquete se verifican con `SigLevel=Required` contra la llave de arriba.

## Personalización

Los ganchos personales (vault, dashboard, backups) NO van hardcodeados:
```bash
cp /usr/share/chemarchy/user.conf.example ~/.config/chemarchy/user.conf && $EDITOR ~/.config/chemarchy/user.conf
```
Vacío = comportamiento genérico (las features personales no corren).
