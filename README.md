# Civilizatio

Prototipo simple en **Godot 4** para iterar una simulación de mapa + humanos.

## Estado actual

- Generación procedural de biomas por tiles.
- Humanos visibles (círculos) sobre el mapa.
- Spawn inicial de humanos sólo en tiles válidos.
- Movimiento aleatorio simple por ticks.
- Agua y montaña bloquean el movimiento.
- Lógica separada en:
  - `Main.gd` (orquestación, ticks y dibujo del mundo)
  - `WorldGrid.gd` (datos/reglas del mapa)
  - `Human.gd` (entidad y movimiento)

## Estructura

- `scenes/Main.tscn`: escena principal del proyecto.
- `scripts/Main.gd`: loop principal, input y spawn/movimiento de humanos.
- `scripts/WorldGrid.gd`: generación de biomas y validación de tiles caminables.
- `scripts/Human.gd`: representación y tick de movimiento de un humano.

## Controles

- `Enter`: regenera el mundo y vuelve a spawnear humanos.

## Notas

- El proyecto se mantiene deliberadamente simple para poder iterar rápido.
- Se evita complejizar IA/pathfinding en esta etapa.
