# Configuración y ejecución del flujo

## Orden obligatorio

```text
1. 01_seleccion_ranking_fotos_hemisfericas_v5.R
2. 02_auditoria_visual_binarizacion_top5_v5.R
```

El segundo script depende del archivo:

```text
03_top_candidatas_LAI_auditoria.csv
```

## Preparación del sitio

Organice las fotografías antes de ejecutar:

```text
Sitio/
├── P1/
│   ├── dosel/
│   └── dosel2m/
├── P2/
│   ├── dosel/
│   └── dosel2m/
└── P3/
    ├── dosel/
    └── dosel2m/
```

No coloque fotografías adicionales dentro de la carpeta de salida.

## Parámetros que deben revisarse en cada sitio

### Ruta raíz

```r
PARAMS$ruta_imagenes
```

### Grupos esperados

```r
PARAMS$grupos_esperados
```

Ejemplo:

```r
data.frame(
  punto = c("P1", "P1", "P2", "P2", "P3", "P3"),
  tipo  = c("dosel", "dosel2m", "dosel", "dosel2m", "dosel", "dosel2m")
)
```

### Fotografías esperadas

```r
PARAMS$fotos_esperadas_por_grupo
```

### Máscara circular

```r
PARAMS$mascara_circular <- list(
  xc = 3000,
  yc = 2000,
  rc = 1500
)
```

Los valores dependen de la geometría de la imagen y del lente.

### Ranking

```r
PARAMS$top_k
PARAMS$pesos_ranking
PARAMS$margen_score_min
```

### Binarización

```r
PARAMS$canal_hemispher
PARAMS$metodo_binarizacion
PARAMS$usar_umbral_zonal
```

## Ejecución desde RStudio

1. Reinicie la sesión de R.
2. Abra el primer script.
3. Edite los parámetros.
4. Ejecute el archivo completo.
5. Revise los CSV.
6. Edite `CONFIG$ruta_csv` en el segundo script.
7. Ejecute el segundo archivo completo.
8. Revise los paneles JPG.

## Ejecución desde Ubuntu o Linux

```bash
cd /ruta/al/repositorio

Rscript --vanilla scripts/01_seleccion_ranking_fotos_hemisfericas_v5.R
Rscript --vanilla scripts/02_auditoria_visual_binarizacion_top5_v5.R
```

## Ejecución desde Windows PowerShell

```powershell
cd "C:\ruta\al\repositorio"

Rscript.exe --vanilla scripts\01_seleccion_ranking_fotos_hemisfericas_v5.R
Rscript.exe --vanilla scripts\02_auditoria_visual_binarizacion_top5_v5.R
```

## Lista de control posterior

- [ ] Se generó `00_resumen_grupos.csv`.
- [ ] Todos los grupos esperados están presentes.
- [ ] El número de fotografías coincide con el protocolo o está justificado.
- [ ] Se generó `02_ranking_fotos.csv`.
- [ ] Se procesó el top esperado por grupo.
- [ ] `estado_hemispher` es `OK` en la mayoría de candidatas.
- [ ] Se generó una selección final por grupo.
- [ ] Se revisaron los casos de `REVISION_VISUAL_RAPIDA`.
- [ ] Se revisaron manualmente los casos obligatorios.
- [ ] Se inspeccionaron los paneles de binarización.
- [ ] Se guardó `sessionInfo()` para la corrida definitiva.

## Datos que no deberían subirse al repositorio

Por tamaño, privacidad y trazabilidad, normalmente no se recomienda incluir:

- fotografías originales;
- copias orientadas;
- resultados completos de campañas;
- carpetas temporales;
- archivos con rutas personales;
- datos de campo sensibles.

Para ejemplos públicos utilice fotografías autorizadas y anonimizadas.
