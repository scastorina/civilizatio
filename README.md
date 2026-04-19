# Civilizatio

Prototipo simple en **Godot 4** para iterar una simulación de mapa + especies.

## Estado actual

- Generación de biomas por tiles con presets de mapa.
- Varias especies visibles con color propio.
- Spawn inicial en tiles caminables (no agua / no montaña).
- Movimiento por ticks sin superposición.
- Evolución básica por especie según biomas preferidos.
- Adelantador de tiempo configurable (x1/x2/x5/x10).
- Editor de terreno en runtime para pintar biomas.
- Menú de configuración para mapa, especies y velocidad.

## Estructura

- `scenes/Main.tscn`: escena principal del proyecto.
- `scripts/Main.gd`: loop principal, menú, editor, spawn, ticks y resumen de evolución.
- `scripts/WorldGrid.gd`: generación de biomas, presets y validación de tiles caminables.
- `scripts/Human.gd`: entidad de especie, movimiento y evolución individual.

## Controles

- `Enter`: regenera el mundo con la configuración seleccionada.
- `Ctrl + N`: inicia una nueva partida (regenera mundo).
- `F5`: guarda la partida actual en `user://savegame.json`.
- `F9`: carga la última partida guardada.
- `E`: activa/desactiva el editor de terreno.
- `1..5`: selecciona bioma para pintar.
  - `1`: water
  - `2`: sand
  - `3`: grass
  - `4`: forest
  - `5`: mountain
- Click izquierdo: pinta el tile seleccionado cuando el editor está activo.

## Menú de configuración

En el panel lateral podés ajustar:

- **Mapa**:
  - Aleatorio
  - Tipo Tierra (bandas latitudinales simples)
  - Continente (masa principal rodeada de agua)
- **Cantidad de especies activas** (1 a 4).
- **Adelantador de tiempo** (x1/x2/x5/x10).
- **Aplicar y regenerar** para refrescar el mundo con esa configuración.

## Ejecutar en Godot 4

1. Abrir Godot 4.
2. Importar esta carpeta (`civilizatio`) como proyecto existente.
3. Ejecutar la escena principal (`scenes/Main.tscn`) o simplemente `Run Project`.

## Notas

- Es una base simple para iterar rápido; la evolución actual es intencionalmente básica.
- El preset “Tipo Tierra” es aproximado (no usa datos reales GIS).
- Próximo paso sugerido: cargar heightmaps reales de Tierra/continentes para mapas más fieles.
