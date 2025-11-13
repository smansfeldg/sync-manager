# Sync Manager

Repositorio central para sincronizar automáticamente ramas de repos GitHub hacia Bitbucket Server (on-premise).

---

## Cómo funciona

1. Cada repo origen (en GitHub) tiene un pequeño workflow que **llama** a este repo (`sync-manager`).
2. El workflow reutilizable de este repo hace el `git push` hacia el Bitbucket correspondiente.
3. La rama `main` está protegida y **no se sincroniza**.

---

## Requisitos

- GitHub CLI (`gh`) instalado y autenticado.
- Permisos admin en los repos a sincronizar.
- Personal Access Token en Bitbucket con permisos `repository:write`.

---

## Configuración

1. Cloná este repo y posicionate en su raíz.
2. Ejecutá el script `bootstrap.sh` pasando los repos a configurar:

   ```bash
   ./scripts/bootstrap.sh myorg/repo1 myorg/repo2
    ```
---

### Ejemplo completo de uso

Supongamos que querés sincronizar el repo
GitHub → Bitbucket:

| Origen (GitHub)                                                                                  | Destino (Bitbucket)                                  |
| ------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| [`https://github.com/smansfeldg/release-tracker`](https://github.com/smansfeldg/release-tracker) | `https://git.gbsj.com.ar/scm/ac/release-tracker.git` |

---

#### Comando a ejecutar

Desde la raíz del repo `sync-manager`, corré:

```bash
./scripts/bootstrap.sh smansfeldg/release-tracker
```

El script te pedirá los datos necesarios:

```
Bitbucket username: sync-bot
Bitbucket PAT: ********************
Bitbucket repo URL (sin https://, ej: git.gbsj.com.ar/scm/mob/home-banking-mobile-bsc.git): git.gbsj.com.ar/scm/ac/release-tracker.git
```

y luego configurará el repo automáticamente:

```
Configuring smansfeldg/release-tracker ...
✅ smansfeldg/release-tracker configurado.
```

---

#### Resultado

* Se crean los *secrets* en tu repo de GitHub:

  * `BITBUCKET_USER`
  * `BITBUCKET_PAT`
  * `BITBUCKET_REPO_URL`

* Se agrega el workflow:

  ```
  .github/workflows/call-sync.yml
  ```

  que llama al reusable workflow del repo `sync-manager`.

* Desde ese momento, **cada push en la rama `develop`** de tu repo GitHub
  se sincroniza automáticamente a la rama `develop` del repo Bitbucket.

---

## Mantenimiento

### Actualizar el workflow en repos existentes

Para actualizar el workflow en repos ya configurados, volvé a ejecutar el script `bootstrap.sh` con los mismos parámetros. El script actualizará automáticamente el archivo de workflow.

### Remover la configuración

Para deshacer la sincronización de un repo:

1. Eliminá manualmente el archivo `.github/workflows/call-sync.yml` del repo origen.
2. Eliminá los secrets del repo usando GitHub CLI:

   ```bash
   gh secret remove BITBUCKET_USER -R owner/repo
   gh secret remove BITBUCKET_PAT -R owner/repo
   gh secret remove BITBUCKET_REPO_URL -R owner/repo
   ```

---

## Contribuciones

Este proyecto sigue las mejores prácticas de automatización y seguridad. Para contribuir:

1. Creá un fork del repositorio.
2. Realizá tus cambios en una rama feature.
3. Enviá un pull request con una descripción clara de los cambios.
