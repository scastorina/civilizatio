# Civilizatio

Prototipo simple en **Godot 4** para iterar una simulación de mapa + humanos.

## Estado actual

- Generación procedural de biomas por tiles.
- Humanos visibles (círculos) sobre el mapa.
- Spawn inicial en tiles caminables (no agua / no montaña).
- Movimiento aleatorio simple por ticks.
- Sin superposición entre humanos durante el movimiento.
- Editor de terreno en runtime para pintar biomas.
- Lógica separada en:
  - `Main.gd` (orquestación, ticks, input y dibujo del mundo)
  - `WorldGrid.gd` (datos/reglas del mapa)
  - `Human.gd` (entidad y decisión de movimiento)

## Estructura

- `scenes/Main.tscn`: escena principal del proyecto.
- `scripts/Main.gd`: loop principal, editor, spawn y ticks.
- `scripts/WorldGrid.gd`: generación de biomas y validación de tiles caminables.
- `scripts/Human.gd`: representación y movimiento de un humano.

## Controles

- `Enter`: regenera el mundo y vuelve a spawnear humanos.
- `E`: activa/desactiva el editor de terreno.
- `1..5`: selecciona bioma para pintar.
  - `1`: water
  - `2`: sand
  - `3`: grass
  - `4`: forest
  - `5`: mountain
- Click izquierdo: pinta el tile seleccionado cuando el editor está activo.

## Ejecutar en Godot 4

1. Abrir Godot 4.
2. Importar esta carpeta (`civilizatio`) como proyecto existente.
3. Ejecutar la escena principal (`scenes/Main.tscn`) o simplemente `Run Project`.

## Notas

- El proyecto se mantiene deliberadamente simple para iterar rápido.
- No hay pathfinding ni IA avanzada en esta etapa.
- Si intentás pintar `water` o `mountain` sobre un humano, se ignora para no dejarlo atrapado en tile bloqueado.
