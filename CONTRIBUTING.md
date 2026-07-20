# Contribuciones

Las contribuciones son bienvenidas, especialmente aquellas relacionadas con:

- validación de umbrales en diferentes tipos de cobertura;
- compatibilidad con otras cámaras y lentes;
- nuevos métodos de binarización;
- pruebas automatizadas;
- reducción del consumo de memoria;
- documentación;
- ejemplos reproducibles;
- validación independiente de métricas de dosel.

## Antes de proponer cambios

1. Cree una rama a partir de la versión actual.
2. No incluya fotografías o datos de campo sin autorización.
3. Mantenga los parámetros configurables al inicio de cada script.
4. Evite rutas absolutas en los cambios que se propongan para integrar.
5. Documente cualquier cambio metodológico.
6. Indique si el cambio modifica resultados anteriores.
7. Pruebe el flujo completo con al menos un sitio de ejemplo.

## Estilo del código

- Use nombres descriptivos.
- Mantenga bloques numerados.
- Evite duplicar funciones.
- Use mensajes claros para errores y progreso.
- Preserve los archivos originales.
- No introduzca paralelización como valor predeterminado cuando aumente el riesgo de errores de memoria.
- Mantenga separada la selección automática de la auditoría visual.

## Reporte de errores

Incluya:

- sistema operativo;
- versión de R;
- salida de `sessionInfo()`;
- nombre del script;
- bloque donde ocurrió el error;
- mensaje completo;
- número de fotografías;
- estructura de carpetas;
- parámetros modificados;
- fragmento mínimo reproducible cuando sea posible.

No publique rutas privadas, nombres sensibles ni fotografías sin autorización.
