# Script 2: auditoría visual de la binarización

**Archivo:** `scripts/02_auditoria_visual_binarizacion_top5_v5.R`

## Propósito

Este script genera figuras de auditoría para revisar visualmente las mejores candidatas seleccionadas por el script principal.

No recalcula el ranking general y no modifica la selección final. Su función es ayudar al analista a verificar si la binarización representa adecuadamente el cielo y la vegetación.

## Dependencia

Debe ejecutarse después de:

```text
01_seleccion_ranking_fotos_hemisfericas_v5.R
```

Lee como entrada:

```text
03_top_candidatas_LAI_auditoria.csv
```

## Entrada principal

```r
CONFIG$ruta_csv
```

Ejemplo:

```r
CONFIG$ruta_csv <- file.path(
  "C:/ruta/al/sitio",
  "resultados_seleccion_fotos",
  "03_top_candidatas_LAI_auditoria.csv"
)
```

## Parámetros principales

| Parámetro | Función |
|---|---|
| `ruta_csv` | Archivo de auditoría generado por el script principal. |
| `csv_es_csv2` | Indica si el CSV usa `;` como separador y `,` como decimal. |
| `carpeta_salida` | Carpeta donde se crean los paneles JPG. |
| `top_n_graficar` | Número de candidatas por grupo que serán representadas. |
| `canal_hemispher` | Canal usado en la importación. |
| `mascara_circular` | Máscara que debe coincidir con la del script principal. |
| `metodo_binarizacion` | Método de binarización. |
| `usar_umbral_zonal` | Activa la binarización zonal. |
| `n_workers` | Número de procesos; el valor `1` es la opción más segura. |
| `ancho_px` y `alto_px` | Dimensiones del JPG. |
| `calidad_jpg` | Calidad de compresión. |

## Columnas requeridas

El CSV debe contener:

```text
sitio
punto
tipo
archivo
ruta_completa
ranking_qc
```

También utiliza, cuando están disponibles:

```text
L
DIFN
cobertura_dosel
```

## Funcionamiento

### 1. Lectura y filtrado

Se conservan las filas con:

```r
ranking_qc <= CONFIG$top_n_graficar
```

### 2. Orientación

Si una fotografía está en posición vertical, se crea una copia horizontal temporal. La original permanece intacta.

### 3. Procesamiento

Para cada candidata:

- se lee la fotografía en color;
- se importa el canal definido;
- se aplica la máscara circular;
- se ejecuta la misma binarización configurada en el script principal;
- se crea un panel de cuatro celdas.

### 4. Contenido del panel

#### Celda 1: fotografía original

Muestra la imagen en color y dibuja:

- borde de la máscara circular;
- centro de la máscara.

#### Celda 2: imagen de proceso

Muestra el canal usado por `hemispheR` antes de binarizar.

#### Celda 3: imagen binarizada

Permite evaluar visualmente la separación entre cielo y vegetación.

#### Celda 4: información

Incluye:

- sitio;
- punto;
- tipo;
- archivo;
- posición en el ranking;
- método de binarización;
- LAI;
- DIFN;
- cobertura de dosel.

## Salidas

La carpeta se crea junto al CSV:

```text
resultados_seleccion_fotos/
└── figuras_revision_binarizacion_top5/
```

Los nombres siguen el patrón:

```text
<sitio>_<punto>_<tipo>_top<ranking>_<archivo>.jpg
```

También se genera:

```text
00_log_figuras_generadas.csv
```

El log identifica:

- fotografía;
- grupo;
- destino del panel;
- resultado `OK` o mensaje de error.

## Ejecución

```bash
Rscript --vanilla scripts/02_auditoria_visual_binarizacion_top5_v5.R
```

## Recomendación de memoria

El valor recomendado es:

```r
n_workers = 1
```

Cada fotografía se procesa a resolución completa. Aumentar los procesos simultáneos puede multiplicar el consumo de memoria.

Solo se recomienda aumentar `n_workers` después de verificar el uso de RAM y el número total de fotografías.

## Criterios de revisión visual

La binarización debe comprobarse especialmente en:

- bordes de hojas;
- claros pequeños;
- troncos o ramas iluminadas;
- cielo parcialmente nublado;
- reflejos;
- zonas saturadas;
- regiones oscuras del dosel;
- borde de la máscara;
- fotografías con diferencias marcadas de exposición.

Una binarización problemática puede producir métricas plausibles numéricamente, pero incorrectas espacialmente.

## Problemas frecuentes

### El CSV no existe

Ejecute primero el script principal y confirme la ruta.

### El CSV no tiene las columnas esperadas

Compruebe que se está usando la salida actual del script principal.

### Las orientaciones no coinciden

Verifique que:

```r
CONFIG$rotar_horizontal_antes_binarizar = TRUE
```

### La máscara aparece desplazada

Revise:

```r
CONFIG$mascara_circular
```

Las coordenadas deben corresponder con la resolución real de la fotografía horizontal.

### Las figuras consumen demasiada memoria

Mantenga:

```r
CONFIG$n_workers = 1
```

Reinicie R antes de ejecutar el lote y cierre otros programas que utilicen mucha memoria.
