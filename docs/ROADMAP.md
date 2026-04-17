# Roadmap de Civilizatio

## Visión
Construir un sandbox 2D de simulación emergente inspirado en WorldBox.

## MVP
- mundo en grilla
- biomas básicos
- regeneración procedural
- humanos simples
- recursos
- herramientas del jugador

## Sistemas siguientes
### Mundo
- humedad
- temperatura
- fuego
- fertilidad

### Entidades
- aldeanos
- animales
- criaturas hostiles

### Civilizaciones
- aldeas
- expansión
- guerra
- cultura

### Interacción del jugador
- pintar agua
- pintar bosque
- lanzar rayos
- meteoritos

## Arquitectura sugerida
- `WorldGrid`
- `BiomeGenerator`
- `EntityManager`
- `TickSystem`
- `CivilizationManager`
- `PowerSystem`
