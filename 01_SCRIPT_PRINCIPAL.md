# Script 1: selección y ranking de fotografías hemisféricas

**Archivo:** `scripts/01_seleccion_ranking_fotos_hemisfericas_v5.R`

## Propósito

Este es el script principal del repositorio. Procesa todas las fotografías de un sitio, evalúa su calidad, genera un ranking por grupo, calcula métricas de dosel para las mejores candidatas y propone una fotografía final.

## Entradas

### Fotografías

El script busca recursivamente archivos con extensiones JPG, JPEG o PNG dentro de:

```r
PARAMS$ruta_imagenes
```

La estructura esperada es:

```text
ruta_imagenes/
└── punto/
    └── tipo/
        └── fotografía
```

Ejemplo:

```text
Sitio38_10marzo2026/P1/dosel/IMG_0001.JPG
```

### Parámetros principales

| Parámetro | Función |
|---|---|
| `ruta_imagenes` | Carpeta raíz del sitio. |
| `carpeta_salida` | Nombre de la carpeta de resultados. |
| `grupos_esperados` | Combinaciones de punto y tipo que deberían existir. |
| `fotos_esperadas_por_grupo` | Número esperado de fotografías por grupo. |
| `canal_calidad` | Canal usado para la evaluación radiométrica. |
| `canal_hemispher` | Canal usado por `hemispheR`. |
| `mascara_circular` | Centro y radio de la región hemisférica válida. |
| `top_k` | Número de candidatas procesadas con `hemispheR`. |
| `metodo_binarizacion` | Método de binarización. |
| `usar_umbral_zonal` | Activa o desactiva la binarización zonal. |

## Etapas de procesamiento

### 1. Preparación

- verifica e instala paquetes cuando corresponde;
- crea la carpeta de salida;
- define funciones auxiliares;
- fija la semilla para el muestreo de píxeles.

### 2. Búsqueda de imágenes

Se listan las imágenes de forma recursiva y se excluyen las que estén dentro de la carpeta de resultados para evitar reprocesar archivos generados.

### 3. Orientación y máscara

Cuando una fotografía está en posición vertical, se crea una copia horizontal de trabajo. El archivo original no se modifica.

La máscara circular se aplica antes de evaluar los píxeles y también antes del cálculo final con `hemispheR`.

### 4. Control de calidad

Para cada fotografía se calculan o verifican:

- saturación;
- subexposición;
- fracción de píxeles luminosos;
- variación radiométrica;
- mezcla gaussiana de dos componentes;
- media y proporción del componente interpretado como cielo;
- Ashman's D;
- traslape entre distribuciones;
- coeficiente de variación del cielo.

El resultado se registra en `01_calidad_fotos.csv`.

### 5. Ranking multicriterio

Solo las fotografías con estado `APTA` entran inicialmente al ranking.

Los criterios se transforman a escalas relativas de 0 a 1 dentro de cada grupo y se combinan mediante pesos configurables:

```r
PARAMS$pesos_ranking
```

El ranking se realiza de forma independiente para cada combinación de:

```text
sitio + punto + tipo
```

### 6. Rescate para completar el top

Cuando un grupo tiene menos fotografías aptas que `top_k`, pueden incorporarse fotografías clasificadas como `CIELO_NO_IDENTIFICABLE`.

Reglas:

- nunca desplazan a una fotografía `APTA`;
- solo ocupan posiciones faltantes;
- se identifican con `origen_seleccion = "RESCATE"`;
- su puntuación relativa se calcula únicamente entre candidatas de rescate.

### 7. Procesamiento con hemispheR

Para el top de candidatas se ejecutan:

```r
import_fisheye()
binarize_fisheye()
gapfrac_fisheye()
canopy_fisheye()
```

Se obtienen, entre otras, métricas como:

- `L`
- `DIFN`
- cobertura de dosel calculada como `100 - DIFN`

### 8. Auditoría de estabilidad

Cada candidata se compara con la mediana del grupo.

Se evalúan diferencias relativas o absolutas en:

- LAI;
- DIFN;
- cobertura de dosel;
- errores de procesamiento.

### 9. Selección final

La fotografía con `ranking_qc == 1` se propone como selección final.

La decisión se clasifica según las alertas acumuladas:

```text
SELECCION_AUTOMATICA
REVISION_VISUAL_RAPIDA
REVISION_MANUAL_OBLIGATORIA
```

## Archivos generados

### `00_resumen_grupos.csv`

Controla:

- grupos esperados;
- grupos encontrados;
- número de imágenes;
- número de aptas;
- posibles carpetas faltantes;
- diferencias respecto al número esperado de fotografías.

### `01_calidad_fotos.csv`

Contiene una fila por fotografía con sus métricas y estado.

### `02_ranking_fotos.csv`

Contiene el ranking y la procedencia de cada candidata:

```text
NORMAL
RESCATE
```

### `03_top_candidatas_LAI_auditoria.csv`

Integra ranking, resultados de `hemispheR` y alertas de estabilidad.

### `04_seleccion_final.csv`

Conserva toda la información de la fotografía seleccionada y la justificación de la decisión.

### `05_resumen_seleccion_final.csv`

Versión resumida para revisión, reporte o integración con otras bases de datos.

## Ejecución

```bash
Rscript --vanilla scripts/01_seleccion_ranking_fotos_hemisfericas_v5.R
```

## Verificaciones previas

Antes de ejecutar:

1. confirmar `PARAMS$ruta_imagenes`;
2. revisar la estructura de carpetas;
3. cerrar los CSV de una corrida anterior si están abiertos en Excel;
4. comprobar que la máscara corresponda con la resolución y orientación de las fotografías;
5. confirmar los grupos esperados;
6. verificar que exista suficiente espacio de almacenamiento.

## Criterios para considerar una corrida exitosa

- aparece el mensaje `Proceso finalizado`;
- se generan los seis CSV principales;
- los grupos esperados aparecen en `00_resumen_grupos.csv`;
- no existen errores masivos de importación;
- `03_top_candidatas_LAI_auditoria.csv` contiene las candidatas esperadas;
- la selección final incluye una fila por grupo procesable.

## Errores frecuentes

### No se encontraron imágenes

Revise:

- la ruta;
- las extensiones;
- los permisos de lectura;
- la estructura de carpetas.

### No hay fotografías aptas para rankear

Puede indicar:

- umbrales demasiado estrictos;
- máscara mal ubicada;
- fotografías subexpuestas;
- fotografías sin cielo visible;
- canal inadecuado.

No se recomienda relajar umbrales sin revisar primero las imágenes y el archivo de calidad.

### No se puede escribir un CSV

La causa más común es que el archivo esté abierto en otro programa. El script intenta crear una copia con un sufijo horario.

### Error de memoria

Reduzca procesos simultáneos, cierre objetos pesados y reinicie la sesión de R antes de una nueva corrida.
