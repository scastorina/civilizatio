# Solución rápida: `git pull` falla con `MERGE_HEAD exists`

Si ves este error:

```text
error: You have not concluded your merge (MERGE_HEAD exists).
hint: Please, commit your changes before merging.
fatal: Exiting because of unfinished merge.
```

significa que quedó una fusión a medio terminar.

## Opción A (recomendada): terminar la fusión

1. Ver conflictos:

```bash
git status
```

2. Resolver archivos con conflicto (`<<<<<<<`, `=======`, `>>>>>>>`).

3. Marcar como resueltos:

```bash
git add .
```

4. Finalizar merge:

```bash
git commit -m "merge: resolve conflicts"
```

5. Volver a actualizar:

```bash
git pull
```

## Opción B: cancelar la fusión incompleta

Si querés descartar esa fusión y volver al estado anterior:

```bash
git merge --abort
```

Luego:

```bash
git pull
```

## Opción C: reset duro (solo si sabés que no necesitás cambios locales)

⚠️ Esto borra cambios locales no confirmados.

```bash
git reset --hard HEAD
git merge --abort 2>$null || true
git pull
```

## Comandos de diagnóstico útiles

```bash
git status
git log --oneline --graph --decorate -n 20
git reflog -n 20
```

## Nota para Windows PowerShell

Si estás en PowerShell y aparece `MERGE_HEAD`, no es problema de PowerShell: es estado interno de Git. Se resuelve con `git commit` o `git merge --abort`.

---

# Cómo asegurarte de que en local tenés todo lo de GitHub

Si querés confirmar que tu copia local está completamente sincronizada con GitHub, seguí esta secuencia:

1. Verificá que exista un remoto (`origin`):

```bash
git remote -v
```

Si no aparece nada, agregalo:

```bash
git remote add origin <URL_DEL_REPO_EN_GITHUB>
```

2. Traé absolutamente todas las referencias remotas:

```bash
git fetch origin --prune --tags
```

3. Posicionate en tu rama principal (ejemplo `main`):

```bash
git checkout main
```

4. Comprobá si estás adelantado/atrasado respecto a GitHub:

```bash
git status -sb
git rev-list --left-right --count HEAD...origin/main
```

- Si ves `0 0`, estás al día.
- Si el número de la derecha es mayor que 0, te faltan cambios remotos.

5. Actualizá tu rama local:

```bash
git pull --rebase origin main
```

6. (Opcional) Si querés que quede idéntica a GitHub descartando cambios locales:

⚠️ Esto elimina commits/cambios locales no publicados.

```bash
git reset --hard origin/main
git clean -fd
```

7. Verificación final:

```bash
git status
git log --oneline --decorate -n 5
```

Si `git status` muestra *working tree clean* y no estás behind de `origin/main`, tu local ya tiene todo lo de GitHub.

## Caso real: `rev-list` da `0 0` pero `pull --rebase` falla

Si te pasa esto:

- `git rev-list --left-right --count HEAD...origin/main` devuelve `0 0`
- pero `git pull --rebase origin main` muestra:
  - `cannot pull with rebase: You have unstaged changes`

**No te faltan commits remotos**. Lo que tenés son cambios locales sin commitear.

Ejemplo típico en Godot:

- `M project.godot`
- `?? scripts/*.gd.uid`

Eso suele pasar por archivos autogenerados al abrir el proyecto.

### Qué hacer (según intención)

1. Si querés descartar esos cambios locales y quedar limpio:

```bash
git restore project.godot
git clean -fd
git status -sb
```

2. Si querés conservarlos temporalmente para poder actualizar:

```bash
git stash push -u -m "wip local godot files"
git pull --rebase origin main
git stash pop
```

3. Si los `.uid` no deben versionarse en tu flujo local, podés ignorarlos en `.git/info/exclude` (solo local, no afecta al repo remoto):

```bash
echo "*.uid" >> .git/info/exclude
```

> Recomendación: en repos Godot compartidos, definan en equipo si los `.uid` se versionan o no para evitar ruido constante.
