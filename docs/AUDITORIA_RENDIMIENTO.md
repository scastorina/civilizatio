# Auditoría técnica de rendimiento y uso de recursos

Fecha: 2026-04-19

## Objetivo
Analizar el comportamiento del código, detectar cuellos de botella y aplicar optimizaciones de bajo riesgo para reducir CPU/memoria por tick.

## Alcance auditado
- `scripts/Main.gd`
- `scripts/WorldEffects.gd`
- Arquitectura del loop de simulación y puntos de mayor complejidad algorítmica.

## Hallazgos principales

### 1) Cálculo diplomático con trabajo repetido
En `Main._update_diplomacy()` se recalculaba religión dominante por especie múltiples veces por par de especies, y además se escaneaban todas las rutas comerciales para cada par.

**Impacto**: coste innecesario en cada tick diplomático, especialmente cuando sube la población/especies activas.

### 2) Incendios con búsqueda O(fuegos × humanos)
En `WorldEffects._tick_fire()` se recorría toda la lista de humanos por cada celda en fuego para marcar estados.

**Impacto**: coste creciente fuerte cuando coinciden más fuegos y población alta.

### 3) Plaga con búsqueda O(sanos × infectados)
En `WorldEffects._tick_plague()` cada humano sano recorría todas las posiciones infectadas.

**Impacto**: complejidad cuadrática en brotes grandes.

## Optimizaciones aplicadas

### A) Caches de diplomacia por tick (`Main.gd`)
- Se agregó `_dominant_religions_for_species()` para calcular religiones dominantes en una pasada.
- Se preconstruye `cross_trade_pairs` para consulta O(1) por par diplomático.
- Se reemplaza el escaneo repetido de `_trade_routes` por lookup directo.

**Resultado esperado**: menor uso de CPU en diplomacia, especialmente en mundos avanzados.

### B) Índice espacial simple para fuego (`WorldEffects.gd`)
- Se agregó `_build_humans_by_cell()` para indexar humanos por celda una vez por tick.
- `_tick_fire()` usa ese índice y evita recorrer `humans` completo por cada fuego.

**Resultado esperado**: mejora significativa cuando hay muchos focos de fuego.

### C) Modelo de infección equivalente, pero más eficiente (`WorldEffects.gd`)
- Se reemplazó el recorrido contra cada infectado por conteo local en vecindad 3x3.
- La probabilidad se mantiene equivalente usando: `1 - (1 - p)^k` con `p=0.04`.

**Resultado esperado**: menor CPU en plagas con comportamiento estadístico consistente.

## Riesgo funcional
Bajo. Los cambios son internos y no alteran API ni estructura de datos pública. El único ajuste probabilístico se implementó con fórmula equivalente al esquema Bernoulli repetido original.

## Recomendaciones siguientes (alto impacto)
1. **Particionar `Main.gd`** en sistemas (`DiplomacySystem`, `EconomySystem`, `ReligionSystem`) para facilitar perfilado aislado.
2. **Evitar loops O(N²)** en `_update_religions()` con grilla espacial de vecindad (igual que el enfoque aplicado en plaga/fuego).
3. **Throttle de sistemas costosos**: ejecutar algunos subsistemas cada `N` ticks (si gameplay lo permite).
4. **Métricas in-game**: exponer tiempo por subsistema (ms) en HUD debug para validar mejoras con datos.

## KPI sugeridos para validar mejora
- ms/tick promedio y p95.
- cantidad de humanos.
- celdas en fuego activas.
- cantidad de rutas comerciales activas.
- tiempo total de `_update_diplomacy`, `_tick_fire`, `_tick_plague`.

