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

2. **Elige el canal de updates:**

   *Opción A (recomendada):*
   ```bash
   chemarchy-channel-set <canal>   # stable, rc, o edge
   ```

   *Opción B (manual):*
   Añade a `/etc/pacman.conf` (después de core/extra/multilib):
   ```ini
   [chemarchy]
   SigLevel = Required DatabaseRequired
   Include = /etc/pacman.d/chemarchy-channel.conf
   ```
   Crea `/etc/pacman.d/chemarchy-channel.conf` reemplazando `<canal>` con `stable`, `rc`, o `edge`:
   ```ini
   Server = https://github.com/chemaw8/chemarchy-repo/releases/download/<canal>/x86_64
   ```

3. **Sincroniza e instala**: `sudo pacman -Syyuu && sudo pacman -S chemarchy`

> Arquitectura `x86_64`. El canal (`stable`, `rc`, o `edge`) es el tag del release en GitHub.
> La db y cada paquete se verifican con `SigLevel=Required` contra la llave de arriba.

## Personalización

Los ganchos personales (vault, dashboard, backups) NO van hardcodeados:
```bash
cp /usr/share/chemarchy/user.conf.example ~/.config/chemarchy/user.conf && $EDITOR ~/.config/chemarchy/user.conf
```
Vacío = comportamiento genérico (las features personales no corren).
