# Guía rápida del código (para continuar el desarrollo)

Este documento resume cómo está organizado el proyecto y qué tocar primero para seguir iterando sin romper el flujo principal.

## 1) Arquitectura actual

El juego corre sobre una escena principal (`scenes/Main.tscn`) con un único nodo raíz `Main` que carga `scripts/Main.gd`.

`Main.gd` funciona como **orquestador**:
- Inicializa mundo, UI, HUD y cámara.
- Ejecuta el loop por ticks (`_process`) con control de velocidad.
- Encadena los sistemas de simulación en orden (movimiento, evolución, recursos, combate, tecnología, diplomacia, eventos y efectos).
- Maneja herramientas del usuario (pintado de biomas, spawn de entidades, poderes).

## 2) Módulos importantes y responsabilidades

### `scripts/Main.gd`
Punto de entrada y composición de sistemas.

Responsabilidades clave:
- Configuración global (constantes de mapa, especies, velocidades, umbrales de tecnología).
- Ciclo principal por ticks.
- Regeneración del mundo y spawn inicial.
- Integración de sistemas de alto nivel:
  - evolución
  - comercio
  - diplomacia / guerras / alianzas
  - cronología (chronicle)
  - consejo/advice
- Render de mapa + overlays (delegando parte visual a HUD/effects).

### `scripts/WorldGrid.gd`
Modelo de datos de la grilla.

Responsabilidades:
- Generación de biomas por preset (`random`, `earth_like`, `continent`).
- Lectura/escritura de tiles.
- Estado territorial por celda:
  - dueño
  - presencia
  - estructuras (camp/village/town)
  - fortificación
  - mejoras
- Reglas auxiliares (walkable, bounds, etc.).

> Regla práctica: si una feature cambia el estado de una celda, normalmente debe pasar por `WorldGrid`.

### `scripts/Human.gd`
Entidad individual por unidad (especie + estado local).

Responsabilidades típicas:
- posición en grilla
- movimiento
- métricas de evolución
- estados temporales (p.ej. fuego/plaga)

### `scripts/WorldEffects.gd`
Sistema desacoplado para efectos de “poderes” y propagaciones.

Incluye:
- Poderes: `meteor`, `lightning`, `fire`, `plague`, `rain`, `blessing`.
- Tick de efectos persistentes (fuego/plaga).
- Estado visual transitorio (`effects`) y celdas incendiadas (`fire_cells`).

### `scripts/GameUI.gd`
UI interactiva principal (panel lateral, tabs, selección de bioma/especie/poder, eventos de usuario).

### `scripts/GameHUD.gd`
Capa visual superior (HUD, minimapa, paneles de información, crónica, indicadores de guerra, etc.).

### `scripts/SpeciesData.gd`
Catálogo/normalización de información por especie y helpers de presentación.

### `scripts/IconDrawer.gd`
Dibujo vectorial de íconos UI sin assets raster.

## 3) Flujo de ejecución por tick (resumen)

En `Main._process(delta)`:
1. Se toma el multiplicador de tiempo actual.
2. Se acumula tiempo hasta alcanzar `MOVE_TICK_SECONDS`.
3. Por cada tick:
   - avanza año
   - mueve entidades
   - actualiza evolución
   - calcula recursos/fuerzas
   - resuelve combate
   - limpia territorios muertos
   - actualiza tecnología
   - avanza efectos del mundo
   - actualiza comercio
   - actualiza religiones
   - actualiza diplomacia
   - ejecuta eventos especiales por especie
   - resuelve tributos vencidos
   - actualiza consejo/crónica
   - avanza marcadores visuales de batalla

Este orden importa; si agregás sistemas nuevos, definí explícitamente **antes/después de qué** deben correr.

## 4) Cómo extender sin dolor (recomendación de estrategia)

### A. Agregar nueva mecánica de mundo (bioma/clima/recurso)
1. Definir datos y reglas base en `WorldGrid.gd`.
2. Integrar tick en `Main.gd` (idealmente como función aislada `_update_X`).
3. Exponer visualización mínima en `GameHUD.gd`/`GameUI.gd`.
4. Agregar evento en crónica si el cambio es relevante para gameplay.

### B. Agregar una nueva especie
1. Añadir entrada en `SPECIES_LIBRARY` en `Main.gd`.
2. Verificar compatibilidad con diccionarios de estado por especie (`_species_*`).
3. Revisar reglas especiales que hoy asumen nombres concretos (Humanos/Elfos/Enanos/Orcos).
4. Ajustar UI para selección/spawn si hace falta.

### C. Agregar un nuevo poder
1. Implementar `WorldEffects._power_<nuevo>()`.
2. Conectarlo en `apply_power`.
3. Exponer botón/selector en `GameUI.gd`.
4. Añadir feedback visual/log (crónica + `effects`).

## 5) Deuda técnica detectada (prioridad sugerida)

1. **`Main.gd` está muy grande**: conviene separar en sub-sistemas (`DiplomacySystem`, `EconomySystem`, `ChronicleSystem`) para reducir acoplamiento.
2. **Tipado parcial**: hay bastante `Dictionary` y `Array` dinámico; introducir clases de estado (o structs Typed Dictionaries) reduciría errores.
3. **Orden de sistemas implícito**: documentar dependencias entre pasos del tick dentro del código para evitar regresiones al insertar nuevas mecánicas.
4. **Testing automatizado ausente**: incluso tests básicos de `WorldGrid` (generación y walkability) darían mucha seguridad.

## 6) Próximos pasos concretos (plan de 3 iteraciones)

### Iteración 1 (rápida)
- Extraer bloques de `Main.gd` a funciones más pequeñas por dominio.
- Crear `docs/SYSTEM_ORDER.md` con el orden oficial del tick.
- Añadir asserts simples en runtime para invariantes críticas (ej.: no owners en celdas no caminables).

### Iteración 2
- Crear `scripts/systems/` e iniciar extracción real:
  - `EconomySystem.gd`
  - `DiplomacySystem.gd`
  - `ChronicleSystem.gd`
- Mantener `Main.gd` como coordinador.

### Iteración 3
- Incorporar tests de lógica pura para `WorldGrid` y helpers de especie.
- Revisar rendimiento de loops por tick con perfilado en mapas grandes.

## 7) Punto de entrada recomendado para retomar desarrollo

Si vas a continuar ya, empezá por:
1. leer `Main.gd` (solo `_ready`, `_process`, `_regenerate_world` y handlers de input),
2. luego `WorldGrid.gd`,
3. después `WorldEffects.gd`,
4. y finalmente `GameUI.gd`/`GameHUD.gd` para entender el wiring de interacción y render.

Con eso ya podés implementar features nuevas con riesgo bajo de romper el loop principal.
