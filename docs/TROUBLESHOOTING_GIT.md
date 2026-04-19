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
