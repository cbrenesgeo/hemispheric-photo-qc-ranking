# ============================================================
# REVISAR BINARIZACION - TOP 5 CANDIDATAS POR GRUPO
#
# Objetivo:
#   Leer "03_top_candidatas_LAI_auditoria.csv" (ya generado por el
#   pipeline principal) y, para las primeras 5 fotos (ranking_qc <= 5)
#   de cada sitio/punto/tipo, generar UN JPG por foto con una cuadricula
#   2x2:
#     [1] foto original (color, proporcion real, sin deformar)
#     [2] imagen en blanco y negro (canal usado por hemispheR, antes de
#         binarizar; es el "proceso" intermedio)
#     [3] imagen binarizada (cielo/vegetacion), proporcion real
#     [4] texto: sitio/punto/tipo, archivo, metodo, L, DIFN, cobertura
#
# Pasos del script:
#   1. Configuracion (rutas y parametros, iguales a los del pipeline
#      principal para que la binarizacion sea la misma que ya corriste).
#   2. Leer el CSV y quedarse solo con ranking_qc <= 5 por grupo.
#   3. Por cada foto: rotar a horizontal si hace falta, importar,
#      binarizar, armar la cuadricula 2x2 y guardarla como JPG.
#   4. (Opcional) correr el paso 3 en paralelo para que sea mas rapido.
# ============================================================
#####
suppressPackageStartupMessages({
  library(hemispheR)
  library(tidyverse)
  library(jpeg)
})

# Si alguna de estas 3 librerias no quedo realmente cargada (ej. conflicto
# de version de 'rlang'), es mejor detenerse aqui con un mensaje claro que
# seguir y terminar generando 9 archivos con "ERROR: could not find function".
paquetes_requeridos <- c("hemispheR", "tidyverse", "jpeg")
paquetes_cargados <- paste0("package:", paquetes_requeridos) %in% search()
if(any(!paquetes_cargados)){
  stop(
    "No se pudieron cargar estos paquetes: ",
    paste(paquetes_requeridos[!paquetes_cargados], collapse = ", "),
    ". Reinicia R (Session > Restart R) y actualiza 'rlang' en una sesion ",
    "limpia (install.packages('rlang')) antes de volver a correr este script."
  )
}

# ------------------------------------------------------------
# 1. CONFIGURACION
# ------------------------------------------------------------
CONFIG <- list(
  
  # Ruta del CSV ya generado por el pipeline principal.
  ruta_csv = "C:/Users/andre/OneDrive/DOCUMENTOS ORDENADOS/PRÁCTICAS/Manejo/Bosque/Sitio38_10marzo2026/resultados_seleccion_fotos/03_top_candidatas_LAI_auditoria.csv",
  
  # El pipeline principal escribe con ; y decimal , (usar_csv2 = TRUE).
  # Dejar en TRUE si no cambiaste esa opcion alla.
  csv_es_csv2 = TRUE,
  
  # Carpeta donde se guardan los JPG de revision (se crea si no existe).
  carpeta_salida = "figuras_revision_binarizacion_top5",
  
  # Cuantas de las candidatas por grupo se grafican (las de mejor ranking).
  top_n_graficar = 5,
  
  # --------------------------------------------------------
  # Estos deben coincidir con los que usaste en el pipeline principal,
  # para que la binarizacion que ves aqui sea la misma que ya calculaste.
  # --------------------------------------------------------
  canal_hemispher = "B",
  mascara_circular = list(xc = 3000, yc = 2000, rc = 1500),
  metodo_binarizacion = "Otsu",
  usar_umbral_zonal = TRUE,
  
  # --------------------------------------------------------
  # Orientacion horizontal antes de binarizar
  #
  # La mascara circular esta definida asumiendo la foto en horizontal.
  # Si una foto llega en vertical, se crea una COPIA de trabajo rotada
  # (el archivo original nunca se toca) y esa copia es la que se usa para
  # las 3 imagenes del panel (color, proceso y binarizada), asi las 3
  # quedan en el mismo sentido y se pueden comparar visualmente.
  # --------------------------------------------------------
  rotar_horizontal_antes_binarizar = TRUE,
  carpeta_temp_rotadas = "00_temp_rotadas_horizontal",
  sobrescribir_temp_rotadas = FALSE,
  
  # --------------------------------------------------------
  # Rendimiento
  # --------------------------------------------------------
  # OJO: aqui cada foto se procesa a RESOLUCION COMPLETA (para que la
  # binarizacion se vea bien), a diferencia del script de calidad que
  # trabaja con imagenes decimadas. Correr varios workers en paralelo
  # multiplica el uso de RAM (cada worker carga su propia imagen pesada
  # al mismo tiempo) y con pocas fotos (top 3 x grupo) la ganancia de
  # tiempo es minima frente al riesgo de quedarte sin memoria
  # ("std::bad_alloc" / "cannot allocate vector").
  # Por eso el default aqui es 1 (secuencial). Solo sube esto si tienes
  # bastante RAM libre (16 GB+) y muchos grupos que procesar.
  n_workers = 1,
  
  # --------------------------------------------------------
  # Tamano/calidad del JPG de salida
  # --------------------------------------------------------
  # Ahora es una cuadricula 2x2 (no un banner ancho), asi que el canvas
  # es aprox. cuadrado.
  ancho_px = 1500,
  alto_px = 1500,
  calidad_jpg = 85
)


# La carpeta de salida siempre cuelga de la misma carpeta donde esta el CSV
# (tu carpeta "resultados_seleccion_fotos"), sin importar cual sea el
# working directory activo de la sesion de R.
CONFIG$carpeta_salida <- file.path(dirname(CONFIG$ruta_csv), CONFIG$carpeta_salida)
CONFIG$carpeta_temp_rotadas <- file.path(CONFIG$carpeta_salida, CONFIG$carpeta_temp_rotadas)

dir.create(CONFIG$carpeta_salida, recursive = TRUE, showWarnings = FALSE)
dir.create(CONFIG$carpeta_temp_rotadas, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# Orientacion horizontal segura (sin magick). El archivo original nunca
# se modifica; si esta en vertical, se crea una copia rotada en
# carpeta_temp_rotadas y se devuelve esa ruta.
# ------------------------------------------------------------

extension_imagen <- function(path){
  tolower(tools::file_ext(path))
}

leer_imagen_array_segura <- function(path){
  ext <- extension_imagen(path)
  
  if(ext %in% c("jpg", "jpeg")){
    return(jpeg::readJPEG(path))
  }
  
  if(ext == "png"){
    if(!requireNamespace("png", quietly = TRUE)) install.packages("png")
    img <- png::readPNG(path)
    if(length(dim(img)) == 3 && dim(img)[3] > 3){
      img <- img[, , 1:3, drop = FALSE]
    }
    return(img)
  }
  
  stop("Formato de imagen no soportado para lectura segura: ", ext)
}

escribir_imagen_array_segura <- function(img, path){
  ext <- extension_imagen(path)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  
  if(ext %in% c("jpg", "jpeg")){
    jpeg::writeJPEG(img, target = path, quality = 0.95)
    return(invisible(path))
  }
  
  if(ext == "png"){
    if(!requireNamespace("png", quietly = TRUE)) install.packages("png")
    png::writePNG(img, target = path)
    return(invisible(path))
  }
  
  stop("Formato de imagen no soportado para escritura segura: ", ext)
}

leer_dimensiones_imagen_segura <- function(path){
  ext <- extension_imagen(path)
  img <- NULL
  
  dims <- tryCatch({
    if(ext %in% c("jpg", "jpeg")){
      img <- jpeg::readJPEG(path, native = TRUE)
    } else if(ext == "png"){
      if(!requireNamespace("png", quietly = TRUE)) install.packages("png")
      img <- png::readPNG(path, native = TRUE)
    } else {
      stop("Formato de imagen no soportado: ", ext)
    }
    
    d <- dim(img)
    c(height = d[1], width = d[2])
  }, error = function(e){
    message("No se pudieron leer dimensiones de ", basename(path), " | ", e$message)
    c(height = NA_real_, width = NA_real_)
  })
  
  rm(img)
  invisible(gc())
  dims
}

rotar_array_90_horario <- function(x){
  d <- dim(x)
  
  if(length(d) == 2){
    return(t(x[nrow(x):1, , drop = FALSE]))
  }
  
  if(length(d) == 3){
    return(aperm(x[dim(x)[1]:1, , , drop = FALSE], c(2, 1, 3)))
  }
  
  stop("La imagen no tiene una estructura matricial esperada.")
}

orientar_array_horizontal <- function(x){
  d <- dim(x)
  if(length(d) < 2) return(x)
  
  if(d[1] > d[2]){
    x <- rotar_array_90_horario(x)
  }
  
  x
}

# Devuelve la ruta a usar para las 3 imagenes del panel: la original si ya
# esta horizontal, o una copia rotada (creada una sola vez, reutilizable
# entre corridas) si esta vertical.
preparar_ruta_horizontal <- function(path, nombre_unico){
  
  if(!isTRUE(CONFIG$rotar_horizontal_antes_binarizar)){
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  
  dims <- leer_dimensiones_imagen_segura(path)
  
  if(!is.finite(dims["height"]) || !is.finite(dims["width"])){
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  
  if(dims["height"] <= dims["width"]){
    return(normalizePath(path, winslash = "/", mustWork = FALSE))
  }
  
  destino <- file.path(
    CONFIG$carpeta_temp_rotadas,
    paste0(nombre_unico, "_horizontal.", extension_imagen(path))
  )
  
  if(file.exists(destino) && !isTRUE(CONFIG$sobrescribir_temp_rotadas)){
    return(normalizePath(destino, winslash = "/", mustWork = FALSE))
  }
  
  ok <- tryCatch({
    img <- leer_imagen_array_segura(path)
    img <- orientar_array_horizontal(img)
    escribir_imagen_array_segura(img, destino)
    rm(img)
    invisible(gc())
    TRUE
  }, error = function(e){
    message("No se pudo crear copia horizontal de ", basename(path), " | ", e$message)
    FALSE
  })
  
  if(isTRUE(ok)){
    normalizePath(destino, winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(path, winslash = "/", mustWork = FALSE)
  }
}

# ------------------------------------------------------------
# 2. LEER EL CSV Y QUEDARSE CON EL TOP 5 POR GRUPO
# ------------------------------------------------------------
leer_top_candidatas <- function(ruta_csv, es_csv2, top_n){
  
  datos <- if(isTRUE(es_csv2)){
    readr::read_csv2(ruta_csv, show_col_types = FALSE)
  } else {
    readr::read_csv(ruta_csv, show_col_types = FALSE)
  }
  
  columnas_esperadas <- c("sitio", "punto", "tipo", "archivo", "ruta_completa", "ranking_qc")
  faltantes <- setdiff(columnas_esperadas, names(datos))
  if(length(faltantes) > 0){
    stop("Al CSV le faltan columnas esperadas: ", paste(faltantes, collapse = ", "))
  }
  
  if(!"L" %in% names(datos)) datos$L <- NA_real_
  if(!"DIFN" %in% names(datos)) datos$DIFN <- NA_real_
  if(!"cobertura_dosel" %in% names(datos)) datos$cobertura_dosel <- 100 - datos$DIFN
  
  datos %>%
    filter(ranking_qc <= top_n) %>%
    arrange(sitio, punto, tipo, ranking_qc)
}

top_candidatas <- leer_top_candidatas(CONFIG$ruta_csv, CONFIG$csv_es_csv2, CONFIG$top_n_graficar)

if(nrow(top_candidatas) == 0){
  stop("No hay filas con ranking_qc <= ", CONFIG$top_n_graficar, " en el CSV indicado.")
}

message("Fotos a graficar: ", nrow(top_candidatas))

# ------------------------------------------------------------
# 3. GENERAR EL PANEL (JPG) PARA UNA FOTO
# ------------------------------------------------------------
graficar_auditoria_foto <- function(fila){
  
  archivo_foto <- fila$ruta_completa[[1]]
  
  nombre_salida <- sprintf(
    "%s_%s_%s_top%d_%s.jpg",
    fila$sitio[[1]], fila$punto[[1]], fila$tipo[[1]],
    fila$ranking_qc[[1]],
    tools::file_path_sans_ext(fila$archivo[[1]])
  )
  destino <- file.path(CONFIG$carpeta_salida, nombre_salida)
  
  resultado <- tryCatch({
    
    # Si la foto esta vertical, esto devuelve una copia rotada (temporal);
    # si ya esta horizontal, devuelve la ruta original sin tocar nada.
    archivo_foto_horizontal <- preparar_ruta_horizontal(
      archivo_foto,
      nombre_unico = tools::file_path_sans_ext(nombre_salida)
    )
    
    # --- Foto original en color, tal como fue tomada (rotada si hizo falta) ---
    img_color <- jpeg::readJPEG(archivo_foto_horizontal)
    
    # --- Imagen "en proceso" (canal usado por hemispheR, sin binarizar) ---
    img_gris <- hemispheR::import_fisheye(
      file = archivo_foto_horizontal,
      channel = CONFIG$canal_hemispher,
      circ.mask = CONFIG$mascara_circular,
      display = FALSE
    )
    
    # --- Imagen binarizada (cielo/vegetacion) ---
    img_bin <- hemispheR::binarize_fisheye(
      img_gris,
      method = CONFIG$metodo_binarizacion,
      zonal = CONFIG$usar_umbral_zonal,
      display = FALSE
    )
    
    # --- Armar el panel: cuadricula 2x2 (original | proceso / binarizada | texto) ---
    jpeg(destino, width = CONFIG$ancho_px, height = CONFIG$alto_px,
         quality = CONFIG$calidad_jpg, res = 120)
    
    layout(matrix(1:4, nrow = 2, byrow = TRUE))
    par(mar = c(1, 1, 3, 1), oma = c(0, 0, 3, 0))
    
    # --- Celda 1: foto original, SIN deformar (proporcion real, mas chica) ---
    d_color <- dim(img_color)
    h_color <- d_color[1]
    w_color <- d_color[2]
    
    plot(NA, xlim = c(0, w_color), ylim = c(0, h_color), asp = 1,
         axes = FALSE, xlab = "", ylab = "", main = "Foto original")
    rasterImage(img_color, 0, 0, w_color, h_color)
    
    # Dibujar la máscara utilizada por hemispheR--
    symbols(
      x = CONFIG$mascara_circular$xc,
      y = h_color - CONFIG$mascara_circular$yc,
      circles = CONFIG$mascara_circular$rc,
      inches = FALSE,
      add = TRUE,
      fg = "red",
      lwd = 3
    )
    
    # Marcar el centro de la máscara
    points(
      CONFIG$mascara_circular$xc,
      h_color - CONFIG$mascara_circular$yc,
      pch = 3,
      col = "red",
      cex = 2,
      lwd = 2
    )
    
    
    
    # --- Celda 2: proceso hemispheR (canal usado, sin binarizar) ---
    plot(img_gris, main = "Proceso hemispheR (blanco y negro)")
    
    # --- Celda 3: binarizada (Otsu), proporcion real, fondo gris del propio raster ---
    plot(img_bin, main = paste0("Binarizada: ", CONFIG$metodo_binarizacion,
                                " | zonal = ", CONFIG$usar_umbral_zonal))
    
    # --- Celda 4: texto de informacion ---
    par(mar = c(0.5, 0.5, 0.5, 0.5))
    plot(0:1, 0:1, type = "n", axes = FALSE, xlab = "", ylab = "")
    
    texto_info <- sprintf(
      "Sitio/punto/tipo:\n%s / %s / %s\n\nArchivo: %s\nRanking: top %d\n\nMetodo: %s (zonal = %s)\n\nL = %s\nDIFN = %s\nCobertura = %s%%",
      fila$sitio[[1]], fila$punto[[1]], fila$tipo[[1]], fila$archivo[[1]], fila$ranking_qc[[1]],
      CONFIG$metodo_binarizacion, CONFIG$usar_umbral_zonal,
      formatC(fila$L[[1]], digits = 3, format = "f"),
      formatC(fila$DIFN[[1]], digits = 2, format = "f"),
      formatC(fila$cobertura_dosel[[1]], digits = 1, format = "f")
    )
    
    text(0.5, 0.5, texto_info, cex = 1.15)
    
    mtext(
      sprintf("%s / %s / %s - top %d - %s", fila$sitio[[1]], fila$punto[[1]], fila$tipo[[1]],
              fila$ranking_qc[[1]], fila$archivo[[1]]),
      outer = TRUE, side = 3, cex = 1.2, font = 2
    )
    
    dev.off()
    
    "OK"
    
  }, error = function(e){
    if(!is.null(dev.list())) dev.off()
    message("ERROR en ", basename(archivo_foto), " | ", e$message)
    paste0("ERROR: ", e$message)
  })
  
  # Liberar memoria explicitamente. Los objetos de terra/hemispheR (SpatRaster)
  # tienen parte de su memoria en C++ y no siempre el garbage collector de R
  # los libera a tiempo entre una foto y otra. Con imagenes a resolucion
  # completa esto es lo que evita quedarse sin RAM al procesar varias fotos.
  suppressWarnings(rm(img_color, img_gris, img_bin))
  gc(verbose = FALSE)
  
  tibble(
    sitio = fila$sitio[[1]], punto = fila$punto[[1]], tipo = fila$tipo[[1]],
    archivo = fila$archivo[[1]], ranking_qc = fila$ranking_qc[[1]],
    destino = destino, resultado = resultado
  )
}

# ------------------------------------------------------------
# 4. CORRER SOBRE TODAS LAS FILAS (EN PARALELO SI HAY VARIOS NUCLEOS)
# ------------------------------------------------------------
n_workers <- CONFIG$n_workers
if(is.null(n_workers)) n_workers <- max(1, parallel::detectCores() - 1)

if(n_workers > 1){
  if(!requireNamespace("furrr", quietly = TRUE)) install.packages("furrr")
  if(!requireNamespace("future", quietly = TRUE)) install.packages("future")
  future::plan(future::multisession, workers = n_workers)
  
  log_resultado <- furrr::future_map_dfr(
    seq_len(nrow(top_candidatas)),
    function(i) graficar_auditoria_foto(top_candidatas[i, ]),
    .options = furrr::furrr_options(seed = TRUE),
    .progress = TRUE
  )
  
  future::plan(future::sequential)
} else {
  log_resultado <- purrr::map_dfr(
    seq_len(nrow(top_candidatas)),
    function(i) graficar_auditoria_foto(top_candidatas[i, ])
  )
}

readr::write_csv2(log_resultado, file.path(CONFIG$carpeta_salida, "00_log_figuras_generadas.csv"))

message("Listo. Figuras guardadas en: ", normalizePath(CONFIG$carpeta_salida))
message("Fallidas: ", sum(log_resultado$resultado != "OK"))

# ============================================================
# FIN DEL SCRIPT
# ============================================================

