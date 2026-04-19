# Roadmap de producción (de prototipo a juego jugable)

## Fase 1 — Estabilizar núcleo (obligatoria)
- Loop automático de simulación (sin intervención manual).
- Estados de ejecución claros: pausa, correr y velocidades.
- Nueva partida / reinicio reproducible.
- Guardar / cargar partida completa.
- Correr 10–20 minutos sin errores de consola.

### Checklist de calidad
- [ ] Sin errores en consola durante una sesión larga.
- [ ] HUD deja claro qué está pasando en cada momento.
- [ ] Eventos legibles y con contexto.

## Fase 2 — Estructura de proyecto
Separar el monolito actual en sistemas por dominio para facilitar mantenimiento.

### Objetivo de estructura
- `scripts/core/`: game manager, turn manager, save manager.
- `scripts/world/`: mundo, tiles, generación.
- `scripts/civilizations/`: IA, diplomacia, guerra.
- `scripts/economy/`: recursos y población.
- `scripts/ui/`: HUD y paneles.

## Fase 3 — Vertical slice jugable (v0.1)
Debe incluir:
- mapa procedural,
- civilizaciones activas,
- crecimiento/caída de población,
- recursos/hambre,
- expansión y guerra simple,
- eventos,
- HUD,
- save/load,
- build exportable para Windows.

## Fase 4 — Profundidad (v0.2)
- Diplomacia avanzada.
- Comercio avanzado.
- Tecnología y edificios.
- Cultura/religión más rica.
- Catástrofes, rebeliones, migraciones.

## Fase 5 — Producción real (v0.3)
- Menú principal.
- Configuración inicial de partida.
- Tutorial básico.
- Sonido/música.
- Balance y optimización final.
- Publicación (itch.io / Steam).

## Métricas para gate de release
- Tiempo promedio por tick y p95.
- FPS estable en simulación x5 con mapa lleno.
- Tasa de errores de consola: 0.
- Duración sesión estable: >= 20 min.
