# Hemispheric Photo QC & Ranking

Flujo reproducible en **R** para el control de calidad, ranking, selección y auditoría visual de fotografías hemisféricas orientadas al análisis de cobertura de dosel, fracción de apertura y área foliar.

El repositorio integra dos etapas complementarias:

1. **Selección y ranking semiautomático:** evalúa todas las fotografías de cada grupo, aplica controles radiométricos, calcula métricas de separabilidad entre cielo y vegetación, genera un ranking multicriterio y procesa las candidatas mejor calificadas con `hemispheR`.
2. **Auditoría visual de la binarización:** genera paneles comparativos para revisar la fotografía original, el canal utilizado por `hemispheR`, la imagen binarizada y las métricas obtenidas.

> El ranking automatiza la revisión inicial, pero no sustituye la validación visual y el criterio técnico del analista.

## Objetivo

Facilitar una selección consistente, documentada y auditable de fotografías hemisféricas cuando en cada punto de muestreo existen múltiples exposiciones, configuraciones de cámara o condiciones de iluminación.

El flujo busca:

- detectar fotografías con problemas de saturación, subexposición o escasa presencia de cielo;
- evaluar la separabilidad radiométrica entre cielo y vegetación;
- ordenar las candidatas dentro de cada sitio, parcela y altura de cámara;
- calcular métricas de dosel con `hemispheR`;
- identificar resultados inestables o atípicos;
- proponer una fotografía final por grupo;
- producir figuras de auditoría para la revisión visual del top de candidatas.

## Scripts

| Orden | Script | Función |
|---|---|---|
| 1 | `scripts/01_seleccion_ranking_fotos_hemisfericas_v5.R` | Ejecuta el control de calidad, ranking, procesamiento con `hemispheR`, auditoría de estabilidad y selección final. |
| 2 | `scripts/02_auditoria_visual_binarizacion_top5_v5.R` | Lee el resultado del primer script y genera paneles JPG para revisar visualmente la binarización de las mejores candidatas. |

## Flujo general

```text
Fotografías originales
        │
        ▼
Control de estructura y calidad radiométrica
        │
        ▼
Clasificación de fotografías aptas y descartadas
        │
        ▼
Ranking multicriterio por sitio/parcela/altura
        │
        ▼
Top 5 de candidatas por grupo
        │
        ▼
Binarización y métricas con hemispheR
        │
        ▼
Auditoría de estabilidad
        │
        ▼
Selección final propuesta
        │
        ▼
Paneles de revisión visual
```

## Estructura esperada de las fotografías

El flujo asume una organización jerárquica como la siguiente:

```text
Sitio38_10marzo2026/
├── P1/
│   ├── dosel/
│   │   ├── IMG_0001.JPG
│   │   └── ...
│   └── dosel2m/
│       ├── IMG_0034.JPG
│       └── ...
├── P2/
│   ├── dosel/
│   └── dosel2m/
└── P3/
    ├── dosel/
    └── dosel2m/
```

La ruta relativa de cada imagen se interpreta como:

```text
sitio / punto / tipo / archivo
```

Los valores de `punto`, `tipo`, grupos esperados y número esperado de fotografías son configurables.

## Requisitos

### Software

- R 4.x
- RStudio, terminal o cualquier entorno capaz de ejecutar scripts de R

### Paquetes principales

```r
hemispheR
tidyverse
mclust
jpeg
png
```

Para procesamiento paralelo opcional en el segundo script:

```r
future
furrr
```

## Configuración mínima

### Script 1

Editar al inicio:

```r
PARAMS$ruta_imagenes
PARAMS$grupos_esperados
PARAMS$fotos_esperadas_por_grupo
PARAMS$mascara_circular
PARAMS$top_k
```

### Script 2

Editar:

```r
CONFIG$ruta_csv
```

La ruta debe apuntar a:

```text
resultados_seleccion_fotos/03_top_candidatas_LAI_auditoria.csv
```

También deben coincidir con el script principal:

```r
CONFIG$canal_hemispher
CONFIG$mascara_circular
CONFIG$metodo_binarizacion
CONFIG$usar_umbral_zonal
```

## Ejecución

Desde RStudio puede abrirse cada archivo y ejecutarse de forma completa.

Desde la terminal:

```bash
Rscript --vanilla scripts/01_seleccion_ranking_fotos_hemisfericas_v5.R
Rscript --vanilla scripts/02_auditoria_visual_binarizacion_top5_v5.R
```

El segundo script solo debe ejecutarse después de que el primero haya generado correctamente el archivo `03_top_candidatas_LAI_auditoria.csv`.

## Salidas del script principal

El primer script crea la carpeta `resultados_seleccion_fotos` dentro del sitio procesado.

| Archivo | Contenido |
|---|---|
| `00_resumen_grupos.csv` | Control de grupos presentes, grupos esperados y número de fotografías. |
| `01_calidad_fotos.csv` | Métricas de calidad y estado de cada fotografía. |
| `02_ranking_fotos.csv` | Ranking multicriterio de fotografías aptas y candidatas de rescate. |
| `03_top_candidatas_LAI_auditoria.csv` | Top de candidatas con métricas de `hemispheR` y auditoría de estabilidad. |
| `04_seleccion_final.csv` | Fotografía propuesta para cada grupo, decisión y justificación. |
| `05_resumen_seleccion_final.csv` | Resumen compacto de la selección final. |

## Salidas de la auditoría visual

El segundo script crea:

```text
resultados_seleccion_fotos/
└── figuras_revision_binarizacion_top5/
    ├── <sitio>_<punto>_<tipo>_top1_<archivo>.jpg
    ├── <sitio>_<punto>_<tipo>_top2_<archivo>.jpg
    ├── ...
    └── 00_log_figuras_generadas.csv
```

Cada panel presenta:

1. fotografía original;
2. canal utilizado por `hemispheR`;
3. imagen binarizada;
4. identificación, ranking, LAI, DIFN y cobertura estimada.

## Estados y decisiones principales

### Estados de calidad

Entre otros, el script puede asignar:

- `APTA`
- `DESCARTADA_SATURACION`
- `DESCARTADA_SUBEXPOSICION`
- `SIN_CIELO_VISIBLE`
- `CIELO_NO_IDENTIFICABLE`
- `CIELO_MINORITARIO`
- `SIN_VARIACION`
- `ERROR_IMPORTACION`
- `ERROR_MCLUST`
- `MODELO_INVALIDO`

### Decisión final

La propuesta final puede quedar clasificada como:

- `SELECCION_AUTOMATICA`
- `REVISION_VISUAL_RAPIDA`
- `REVISION_MANUAL_OBLIGATORIA`

La columna `justificacion` resume las razones de cada decisión.

## Principios metodológicos

- La máscara circular se aplica de manera consistente en la evaluación de calidad y en el procesamiento final.
- Las fotografías verticales se convierten en copias horizontales de trabajo; los archivos originales no se modifican.
- El ranking se calcula dentro de cada combinación de sitio, punto y tipo.
- Las fotografías clasificadas como aptas conservan prioridad sobre cualquier candidata de rescate.
- El cálculo de LAI, DIFN y cobertura se limita al top de candidatas.
- La estabilidad se evalúa comparando cada candidata con las medianas del grupo.
- La selección final debe acompañarse de revisión visual cuando existen alertas.

## Limitaciones

- Los umbrales fueron diseñados como controles operativos y pueden requerir calibración para otros sensores, lentes, resoluciones o tipos de cobertura.
- La mezcla gaussiana es una aproximación radiométrica y no garantiza por sí sola una clasificación correcta de cielo y vegetación.
- Una fotografía con buen ranking puede contener artefactos espaciales que solo son detectables mediante revisión visual.
- La máscara circular depende de que sus coordenadas correspondan con la geometría real de la imagen.
- Las métricas dependen del método y parámetros de binarización seleccionados.

## Reproducibilidad

Para documentar una corrida se recomienda conservar:

- versión de los scripts;
- parámetros utilizados;
- estructura original de carpetas;
- archivos CSV generados;
- paneles de auditoría;
- versión de R;
- versiones de los paquetes.

Puede registrarse la sesión con:

```r
sessionInfo()
```

## Cita

Consulte `CITATION.cff`. Antes de publicar una versión del repositorio, complete autores, afiliaciones, DOI o URL definitiva.

## Licencia

Se recomienda una licencia permisiva como MIT cuando se desea facilitar reutilización y adaptación. Revise `LICENSE_RECOMMENDATION.md` antes de publicar.

## Documentación adicional

- `docs/CONFIGURACION_Y_EJECUCION.md`
- `docs/01_SCRIPT_PRINCIPAL.md`
- `docs/02_AUDITORIA_VISUAL.md`
- `docs/GITHUB_REPOSITORY_METADATA.md`
