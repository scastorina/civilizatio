# Civilizatio

Prototipo simple en **Godot 4** para iterar una simulación de mapa + humanos.

## Estado actual

- Generación procedural de biomas por tiles.
- Humanos visibles (círculos) sobre el mapa.
- Spawn inicial en tiles caminables (no agua / no montaña).
- Movimiento aleatorio simple por ticks.
- Sin superposición entre humanos durante el movimiento.
- Lógica separada en:
  - `Main.gd` (orquestación, ticks y dibujo del mundo)
  - `WorldGrid.gd` (datos/reglas del mapa)
  - `Human.gd` (entidad y decisión de movimiento)

## Estructura

- `scenes/Main.tscn`: escena principal del proyecto.
- `scripts/Main.gd`: loop principal, input, spawn y ticks.
- `scripts/WorldGrid.gd`: generación de biomas y validación de tiles caminables.
- `scripts/Human.gd`: representación y movimiento de un humano.

## Controles

- `Enter`: regenera el mundo y vuelve a spawnear humanos.

## Ejecutar en Godot 4

1. Abrir Godot 4.
2. Importar esta carpeta (`civilizatio`) como proyecto existente.
3. Ejecutar la escena principal (`scenes/Main.tscn`) o simplemente `Run Project`.

## Notas

- El proyecto se mantiene deliberadamente simple para iterar rápido.
- No hay pathfinding ni IA avanzada en esta etapa.
