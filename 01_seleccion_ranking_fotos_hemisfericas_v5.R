# ============================================================
# 01_seleccion_ranking_fotos_hemisfericas_v5.R
# Auditoria y seleccion semi-automatica de fotos hemisfericas
#
# Objetivo operativo:
#   1) Leer todas las fotografias hemisfericas dentro de una ruta.
#   2) Evaluar calidad radiometrica de cada fotografia.
#   3) Rankear candidatas por sitio/parcela/altura de camara.
#   4) Calcular metricas de dosel con hemispheR para el top N.
#   5) Seleccionar una foto final por grupo con decision auditada.
#
# Nota metodologica:
#   El ranking radiometrico NO se interpreta como verdad final.
#   La seleccion final combina:
#     - calidad radiometrica,
#     - separabilidad cielo/vegetacion,
#     - estabilidad de LAI, DIFN y cobertura entre candidatas,
#     - banderas de revision visual.
#
# Cambios acumulados de esta version:
#   - Se conserva la orientacion automatica a horizontal de fotos verticales
#     (copia de trabajo; el archivo original nunca se modifica).
#   - Se conserva la eliminacion del criterio de nitidez.
#   - CORRECCION METODOLOGICA CLAVE: la mascara circular ahora se aplica
#     de forma CONSISTENTE en las dos fases que leen pixeles de la imagen:
#       (a) evaluacion de calidad/ranking (procesar_calidad_imagen), y
#       (b) calculo final de metricas de dosel con hemispheR.
#     En v2_5 la mascara solo se aplicaba en (b). Esto permitia que el
#     marco negro fuera del circulo hemisferico (pixeles ~0) entrara al
#     calculo de subexposicion y al ajuste del modelo mclust durante el
#     ranking, inflando artificialmente la subexposicion estimada y
#     sesgando la seleccion de la foto top 1 en algunos grupos.
#   - Como la mascara circular asume la foto en orientacion horizontal,
#     la orientacion automatica (antes usada solo para el top_k) ahora se
#     aplica tambien antes de evaluar calidad, para que la mascara caiga
#     siempre sobre la zona correcta del sensor.
# ============================================================

# ============================================================
# 00. CONTROLES GENERALES
# ============================================================

PARAMS <- list(
  
  # ----------------------------------------------------------
  # Ruta de trabajo
  # ----------------------------------------------------------
  ruta_imagenes = "C:/Users/andre/OneDrive/DOCUMENTOS ORDENADOS/PRÁCTICAS/Manejo/Bosque/Sitio38_10marzo2026",
  carpeta_salida = "resultados_seleccion_fotos",
  
  # ----------------------------------------------------------
  # Paquetes
  # ----------------------------------------------------------
  instalar_paquetes_si_faltan = TRUE,
  paquetes = c("hemispheR", "tidyverse", "mclust", "jpeg", "png"),
  
  # ----------------------------------------------------------
  # Busqueda de imagenes
  # ----------------------------------------------------------
  extensiones_imagen = "\\.(jpe?g|png)$",
  
  # Segun el protocolo de campo de esta campana, por cada grupo se esperan
  # 33 fotografias: 3 en modo P, 15 en Tv y 15 en Av.
  fotos_esperadas_por_grupo = 33,
  
  # Grupos esperados dentro del sitio. Sirve para detectar carpetas faltantes.
  # Si en otra campana hay mas parcelas, modificar esta tabla al inicio.
  usar_grupos_esperados = TRUE,
  grupos_esperados = data.frame(
    punto = c("P1", "P1", "P2", "P2"),
    tipo  = c("dosel", "dosel2m", "dosel", "dosel2m"),
    stringsAsFactors = FALSE
  ),
  
  # ----------------------------------------------------------
  # Lectura de imagen y mascara circular
  #
  # IMPORTANTE (correccion metodologica v4): la mascara circular se aplica
  # de forma CONSISTENTE en la fase de calidad/seleccion Y en el calculo
  # final de hemispheR. Asi, la evaluacion de calidad (saturacion,
  # subexposicion, modelo mclust cielo/vegetacion) se realiza SOLO dentro
  # del circulo hemisferico, igual que el calculo de LAI/DIFN del top_k.
  # Esto evita que el marco negro fuera del circulo (pixeles ~0, ajenos a
  # la escena fotografiada) se cuente como subexposicion o contamine el
  # ajuste del modelo de mezcla.
  # ----------------------------------------------------------
  canal_calidad = "B",
  canal_hemispher = "B",
  mascara_circular = list(
    xc = 3000,
    yc = 2000,
    rc = 1500
  ),
  
  # ----------------------------------------------------------
  # Orientacion horizontal antes de aplicar la mascara
  #
  # La mascara circular esta definida en coordenadas que asumen la foto en
  # horizontal. Si una fotografia llega en vertical, se crea una COPIA de
  # trabajo rotada (el archivo original nunca se modifica) antes de aplicar
  # la mascara. En v4 esto aplica tanto en la fase de calidad/ranking como
  # en el calculo final de hemispheR, para que la mascara caiga siempre
  # sobre la zona correcta del sensor en ambas fases.
  # ----------------------------------------------------------
  orientar_para_mascara = TRUE,
  carpeta_imagenes_orientadas = "00_imagenes_orientadas_mascara",
  sobrescribir_imagenes_orientadas = FALSE,
  
  # ----------------------------------------------------------
  # Filtros y banderas de exposicion
  # ----------------------------------------------------------
  umbral_saturacion = 250,
  
  # Descarte duro. Por encima de este valor la foto se elimina del ranking.
  max_saturacion_descartar = 0.25,
  
  # Bandera de revision. No descarta, pero obliga al menos revision visual rapida.
  max_saturacion_revision = 0.10,
  
  # Subexposicion: ahora SI actua como control real. En bosques tropicales,
  # una foto con mas del 85% de pixeles muy oscuros ya es vegetacion en silueta.
  umbral_subexposicion = 5,
  max_subexposicion_descartar = 0.85,   # antes 1.00 (nunca descartaba)
  max_subexposicion_revision = 0.60,    # antes 0.90 (demasiado permisivo)
  
  # ----------------------------------------------------------
  # Validacion de que el componente "cielo" sea real (nuevo)
  # El script asumia que la gaussiana de mayor media era el cielo, sin
  # verificar que esa media estuviera en zona clara ni que tuviera peso
  # suficiente en la mezcla. Estos tres controles cierran ese hueco.
  # ----------------------------------------------------------
  umbral_mu_cielo_min = 105,           # el "cielo" debe tener media > 120 en el canal usado
  umbral_prop_cielo = 0.05,            # el componente "cielo" debe pesar al menos 5% de la mezcla
  umbral_valor_pixel_cielo = 130,      # valor de intensidad para contar un pixel como "cielo bruto"
  umbral_fraccion_cielo_bruto = 0.03,  # se espera al menos 5% de pixeles > umbral_valor_pixel_cielo
  
  min_valores_unicos = 20,
  
  # ----------------------------------------------------------
  # Modelo de mezcla para separabilidad cielo/vegetacion
  # ----------------------------------------------------------
  n_muestra_mclust = 10000,
  n_grupos_mclust = 2,
  semilla = 123,
  
  # ----------------------------------------------------------
  # Banderas de revision tecnica
  # ----------------------------------------------------------
  umbral_cv_cielo = 0.35,
  ashman_min_revision = 2.0,
  overlap_max_revision = 0.20,
  
  # ----------------------------------------------------------
  # Ranking multicriterio
  # Los pesos se normalizan automaticamente si no suman 1.
  # ----------------------------------------------------------
  pesos_ranking = c(
    ashman = 0.30,          # mas alto = mejor separacion
    overlap = 0.25,         # mas bajo = mejor separacion
    saturacion = 0.10,      # mas bajo = mejor
    subexposicion = 0.15,   # mas bajo = mejor (peso elevado: control real)
    cv_cielo = 0.10,        # mas bajo = cielo mas homogeneo
    fraccion_cielo = 0.10   # mas alto = mas cielo visible detectado
  ),
  
  # ----------------------------------------------------------
  # Calculo de metricas con hemispheR
  # ----------------------------------------------------------
  top_k = 5,
  metodo_binarizacion = "Otsu",
  usar_umbral_zonal = TRUE,
  maxVZA = 70,
  nrings = 7,
  nseg = 24,
  
  # ----------------------------------------------------------
  # Auditoria de estabilidad de resultados
  # ----------------------------------------------------------
  umbral_dif_L_pct = 20,
  umbral_dif_DIFN_pct = 20,
  umbral_dif_cobertura_puntos = 15,
  
  # Si el score del top 1 y top 2 es muy cercano, la decision pasa a
  # revision visual rapida. No implica que el top 1 este mal.
  margen_score_min = 0.05,
  
  # ----------------------------------------------------------
  # Escritura de archivos
  # ----------------------------------------------------------
  usar_csv2 = TRUE              # TRUE: separador ; decimal , para Excel en espanol
)

# ============================================================
# 01. PAQUETES Y CARPETAS
# ============================================================

instalar_si_falta <- function(pkg){
  if(!requireNamespace(pkg, quietly = TRUE)){
    install.packages(pkg, dependencies = TRUE)
  }
}

if(isTRUE(PARAMS$instalar_paquetes_si_faltan)){
  invisible(lapply(PARAMS$paquetes, instalar_si_falta))
}

suppressPackageStartupMessages({
  library(hemispheR)
  library(tidyverse)
  library(mclust)
})

set.seed(PARAMS$semilla)

DIR_SALIDA <- file.path(PARAMS$ruta_imagenes, PARAMS$carpeta_salida)
dir.create(DIR_SALIDA, recursive = TRUE, showWarnings = FALSE)

escribir_tabla <- function(x, nombre_archivo){
  destino <- file.path(DIR_SALIDA, nombre_archivo)
  
  resultado <- tryCatch({
    if(isTRUE(PARAMS$usar_csv2)){
      readr::write_csv2(x, destino)
    } else {
      readr::write_csv(x, destino)
    }
    message("Archivo exportado: ", destino)
    destino
  }, error = function(e){
    # Causa mas comun: el archivo esta abierto en Excel u otro programa
    # (Windows lo bloquea para escritura). En vez de abortar toda la
    # corrida, avisamos y seguimos con el resto del pipeline.
    destino_alterno <- file.path(
      DIR_SALIDA,
      paste0(tools::file_path_sans_ext(nombre_archivo), "_", format(Sys.time(), "%H%M%S"),
             ".", tools::file_ext(nombre_archivo))
    )
    
    warning(
      "No se pudo escribir '", destino, "'. ",
      "Verifica que no este abierto en Excel u otro programa. ",
      "Se intentara guardar como: '", destino_alterno, "'. Detalle: ", e$message,
      call. = FALSE
    )
    
    tryCatch({
      if(isTRUE(PARAMS$usar_csv2)){
        readr::write_csv2(x, destino_alterno)
      } else {
        readr::write_csv(x, destino_alterno)
      }
      message("Archivo exportado (nombre alterno): ", destino_alterno)
      destino_alterno
    }, error = function(e2){
      warning("Tampoco se pudo escribir el archivo alterno. Revisa permisos de la carpeta: ",
              DIR_SALIDA, call. = FALSE)
      NA_character_
    })
  })
  
  invisible(resultado)
}

# ============================================================
# 02. FUNCIONES AUXILIARES
# ============================================================

normalizar_pesos <- function(pesos){
  s <- sum(pesos)
  if(!is.finite(s) || s <= 0){
    stop("Los pesos del ranking deben sumar un valor positivo.")
  }
  pesos / s
}

rank01_high <- function(x){
  x <- as.numeric(x)
  out <- rep(NA_real_, length(x))
  ok <- is.finite(x)
  
  if(sum(ok) == 0) return(out)
  if(sum(ok) == 1){
    out[ok] <- 1
    return(out)
  }
  if(diff(range(x[ok], na.rm = TRUE)) == 0){
    out[ok] <- 1
    return(out)
  }
  
  out[ok] <- (rank(x[ok], ties.method = "average") - 1) / (sum(ok) - 1)
  out
}

rank01_low <- function(x){
  r <- rank01_high(x)
  ifelse(is.na(r), NA_real_, 1 - r)
}

crear_args_import_fisheye <- function(archivo, canal, usar_mascara = TRUE){
  # Cambio v4: usar_mascara ahora es TRUE por defecto, porque la mascara
  # circular debe aplicarse en toda lectura de pixeles (calidad y
  # hemispheR). Se conserva el parametro por si se necesita desactivarla
  # puntualmente (p. ej. pruebas de diagnostico).
  args <- list(
    file = archivo,
    channel = canal,
    display = FALSE
  )
  
  if(isTRUE(usar_mascara) && !is.null(PARAMS$mascara_circular)){
    args$circ.mask <- PARAMS$mascara_circular
  }
  
  args
}

# ------------------------------------------------------------
# Orientacion horizontal segura, usada ANTES de aplicar la mascara
# circular en cualquiera de las dos fases (calidad/ranking y calculo
# final de hemispheR). El archivo original NUNCA se modifica; se crea una
# copia de trabajo dentro de la carpeta de salida.
# ------------------------------------------------------------

normalizar_ruta <- function(x){
  normalizePath(x, winslash = "/", mustWork = FALSE)
}

ruta_relativa_segura <- function(f, ruta_base){
  ruta_norm <- normalizar_ruta(ruta_base)
  f_norm <- normalizar_ruta(f)
  prefijo <- paste0(ruta_norm, "/")
  
  if(startsWith(f_norm, prefijo)){
    substr(f_norm, nchar(prefijo) + 1, nchar(f_norm))
  } else {
    basename(f_norm)
  }
}

extension_imagen <- function(path){
  tolower(tools::file_ext(path))
}

leer_imagen_array_segura <- function(path){
  ext <- extension_imagen(path)
  
  if(ext %in% c("jpg", "jpeg")){
    return(jpeg::readJPEG(path))
  }
  
  if(ext == "png"){
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

# Si la foto ya esta horizontal, devuelve la ruta original (sin copia).
# Si esta vertical, crea (o reutiliza) una copia horizontal en
# DIR_SALIDA/carpeta_imagenes_orientadas/ y devuelve esa ruta.
# Usada tanto antes de evaluar calidad (todas las fotos) como antes del
# calculo final de hemispheR (top_k), para que la mascara circular quede
# siempre alineada con la orientacion asumida (horizontal).
preparar_ruta_horizontal_para_mascara <- function(path){
  
  if(!isTRUE(PARAMS$orientar_para_mascara)){
    return(normalizar_ruta(path))
  }
  
  dims <- leer_dimensiones_imagen_segura(path)
  
  if(!is.finite(dims["height"]) || !is.finite(dims["width"])){
    return(normalizar_ruta(path))
  }
  
  if(dims["height"] <= dims["width"]){
    return(normalizar_ruta(path))
  }
  
  rel <- ruta_relativa_segura(path, PARAMS$ruta_imagenes)
  destino <- file.path(DIR_SALIDA, PARAMS$carpeta_imagenes_orientadas, rel)
  
  if(file.exists(destino) && !isTRUE(PARAMS$sobrescribir_imagenes_orientadas)){
    return(normalizar_ruta(destino))
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
  
  if(isTRUE(ok)) normalizar_ruta(destino) else normalizar_ruta(path)
}

extraer_metadata <- function(f, ruta_base){
  
  ruta_norm <- normalizePath(ruta_base, winslash = "/", mustWork = FALSE)
  f_norm <- normalizePath(f, winslash = "/", mustWork = FALSE)
  
  # Estructura esperada: ruta_base/P1/dosel/IMG_0000.JPG
  prefijo <- paste0(ruta_norm, "/")
  rel <- ifelse(
    startsWith(f_norm, prefijo),
    substr(f_norm, nchar(prefijo) + 1, nchar(f_norm)),
    basename(f_norm)
  )
  
  partes <- strsplit(rel, "/")[[1]]
  n <- length(partes)
  
  tibble(
    sitio = basename(ruta_norm),
    punto = ifelse(n >= 3, partes[n - 2], NA_character_),
    tipo = ifelse(n >= 2, partes[n - 1], NA_character_),
    archivo = basename(f),
    ruta_completa = f_norm,
    profundidad_relativa = n - 1,
    estructura_ok = (n == 3)
  )
}

ashman_d <- function(mu1, mu2, sd1, sd2){
  sqrt(2) * abs(mu2 - mu1) / sqrt(sd1^2 + sd2^2)
}

calc_overlap <- function(mu1, mu2, sd1, sd2){
  # Integral numerica aproximada del area comun entre dos densidades normales.
  # Resultado esperado: 0 = sin traslape, 1 = traslape alto.
  x <- seq(0, 255, length.out = 1000)
  d1 <- dnorm(x, mean = mu1, sd = sd1)
  d2 <- dnorm(x, mean = mu2, sd = sd2)
  dx <- diff(x)[1]
  sum(pmin(d1, d2)) * dx
}

resultado_no_apta <- function(meta, estado, saturacion = NA_real_, subexposicion = NA_real_,
                              fraccion_cielo_bruto = NA_real_, mu_cielo = NA_real_, prop_cielo = NA_real_){
  meta %>%
    mutate(
      saturacion = saturacion,
      subexposicion = subexposicion,
      fraccion_cielo_bruto = fraccion_cielo_bruto,
      mu_cielo = mu_cielo,
      prop_cielo = prop_cielo,
      ashmanD = NA_real_,
      overlap = NA_real_,
      cv_cielo = NA_real_,
      usar_zonal_sugerido = NA,
      estado = estado,
      flag_saturacion_revision = NA,
      flag_subexposicion_revision = NA,
      flag_cv_cielo = NA,
      flag_ashman_bajo = NA,
      flag_overlap_alto = NA
    )
}

procesar_calidad_imagen <- function(f){
  
  meta <- extraer_metadata(f, PARAMS$ruta_imagenes)
  
  # Cambio v4: se orienta a horizontal (si aplica) ANTES de leer la imagen,
  # para que la mascara circular (aplicada a continuacion, ver
  # crear_args_import_fisheye) caiga sobre la zona correcta del sensor.
  # El archivo original nunca se modifica; si la foto viene vertical se usa
  # una copia de trabajo horizontal.
  f_calidad <- preparar_ruta_horizontal_para_mascara(f)
  
  img <- tryCatch({
    do.call(
      hemispheR::import_fisheye,
      crear_args_import_fisheye(f_calidad, PARAMS$canal_calidad, usar_mascara = TRUE)
    )
  }, error = function(e){
    message("Error importando imagen: ", basename(f), " | ", e$message)
    return(NULL)
  })
  
  if(is.null(img)){
    return(resultado_no_apta(meta, "ERROR_IMPORTACION"))
  }
  
  pix <- as.vector(img)
  pix <- pix[is.finite(pix)]
  
  if(length(pix) == 0){
    return(resultado_no_apta(meta, "SIN_PIXELES_VALIDOS"))
  }
  
  saturacion <- mean(pix >= PARAMS$umbral_saturacion)
  subexposicion <- mean(pix <= PARAMS$umbral_subexposicion)
  
  # Fraccion de pixeles claramente luminosos ("cielo bruto"), independiente
  # del modelo mclust. Si no hay minimo de cielo visible, la foto no sirve
  # para estimar variables de dosel.
  fraccion_cielo_bruto <- mean(pix > PARAMS$umbral_valor_pixel_cielo)
  
  if(saturacion > PARAMS$max_saturacion_descartar){
    return(resultado_no_apta(meta, "DESCARTADA_SATURACION", saturacion, subexposicion, fraccion_cielo_bruto))
  }
  
  if(subexposicion > PARAMS$max_subexposicion_descartar){
    return(resultado_no_apta(meta, "DESCARTADA_SUBEXPOSICION", saturacion, subexposicion, fraccion_cielo_bruto))
  }
  
  if(fraccion_cielo_bruto < PARAMS$umbral_fraccion_cielo_bruto){
    return(resultado_no_apta(meta, "SIN_CIELO_VISIBLE", saturacion, subexposicion, fraccion_cielo_bruto))
  }
  
  pix_muestra <- sample(
    pix,
    size = min(PARAMS$n_muestra_mclust, length(pix))
  )
  
  if(length(unique(pix_muestra)) < PARAMS$min_valores_unicos){
    return(resultado_no_apta(meta, "SIN_VARIACION", saturacion, subexposicion, fraccion_cielo_bruto))
  }
  
  modelo <- tryCatch({
    mclust::Mclust(pix_muestra, G = PARAMS$n_grupos_mclust, verbose = FALSE)
  }, error = function(e){
    message("Error Mclust en imagen: ", basename(f), " | ", e$message)
    return(NULL)
  })
  
  if(is.null(modelo)){
    return(resultado_no_apta(meta, "ERROR_MCLUST", saturacion, subexposicion, fraccion_cielo_bruto))
  }
  
  medias <- as.numeric(modelo$parameters$mean)
  orden <- order(medias)
  medias <- medias[orden]
  
  # Proporciones de la mezcla en el mismo orden que las medias: dicen que
  # tan grande es cada componente dentro del modelo.
  proporciones <- as.numeric(modelo$parameters$pro)[orden]
  
  mu1 <- medias[1]
  mu2 <- medias[2]
  prop_cielo <- proporciones[2]
  
  # ------------------------------------------------------------
  # Guardar el estado, pero NO detener el procesamiento.
  # Las métricas (Ashman, overlap, CV, etc.) se calcularán igual.
  # ------------------------------------------------------------
  
  estado_final <- "APTA"
  
  # Validacion 1: la gaussiana de mayor media debe caer en zona clara.
  # Si ambas gaussianas quedan en la zona oscura (ej. dosel muy denso o
  # foto subexpuesta), mclust puede separar "numericamente" sin que exista
  # cielo real.
  if(mu2 < PARAMS$umbral_mu_cielo_min){
    estado_final <- "CIELO_NO_IDENTIFICABLE"
  }
  
  # Validacion 2: el componente "cielo" debe tener peso suficiente en la
  # mezcla. Si es minoritario, la separacion no representa cielo real.
  if(prop_cielo < PARAMS$umbral_prop_cielo){
    estado_final <- "CIELO_MINORITARIO"
  }
  
  sigmasq <- modelo$parameters$variance$sigmasq
  
  if(length(sigmasq) == 1){
    sd1 <- sqrt(sigmasq)
    sd2 <- sqrt(sigmasq)
  } else {
    sigmas <- sqrt(as.numeric(sigmasq))[orden]
    sd1 <- sigmas[1]
    sd2 <- sigmas[2]
  }
  
  parametros <- c(mu1, mu2, sd1, sd2)
  
  if(any(!is.finite(parametros)) || sd1 <= 0 || sd2 <= 0){
    return(resultado_no_apta(meta, "MODELO_INVALIDO", saturacion, subexposicion, fraccion_cielo_bruto, mu2, prop_cielo))
  }
  
  D <- ashman_d(mu1, mu2, sd1, sd2)
  
  if(!is.finite(D)){
    return(resultado_no_apta(meta, "ASHMAN_INVALIDO", saturacion, subexposicion, fraccion_cielo_bruto, mu2, prop_cielo))
  }
  
  overlap <- calc_overlap(mu1, mu2, sd1, sd2)
  
  umbral_cielo <- mean(c(mu1, mu2))
  pix_cielo <- pix[pix > umbral_cielo]
  
  if(length(pix_cielo) < 10 || mean(pix_cielo) == 0){
    cv_cielo <- NA_real_
  } else {
    cv_cielo <- sd(pix_cielo) / mean(pix_cielo)
  }
  
  usar_zonal_sugerido <- ifelse(
    is.na(cv_cielo),
    NA,
    cv_cielo > PARAMS$umbral_cv_cielo
  )
  
  meta %>%
    mutate(
      saturacion = saturacion,
      subexposicion = subexposicion,
      fraccion_cielo_bruto = fraccion_cielo_bruto,
      mu_cielo = mu2,
      prop_cielo = prop_cielo,
      ashmanD = D,
      overlap = overlap,
      cv_cielo = cv_cielo,
      usar_zonal_sugerido = usar_zonal_sugerido,
      estado = estado_final,
      flag_saturacion_revision = saturacion > PARAMS$max_saturacion_revision,
      flag_subexposicion_revision = subexposicion > PARAMS$max_subexposicion_revision,
      flag_cv_cielo = ifelse(is.na(cv_cielo), NA, cv_cielo > PARAMS$umbral_cv_cielo),
      flag_ashman_bajo = D < PARAMS$ashman_min_revision,
      flag_overlap_alto = overlap > PARAMS$overlap_max_revision
    )
}


aplicar_ranking <- function(calidad){
  
  pesos <- normalizar_pesos(PARAMS$pesos_ranking)
  
  calidad %>%
    filter(estado == "APTA") %>%
    group_by(sitio, punto, tipo) %>%
    mutate(
      r_ashman = rank01_high(ashmanD),
      r_overlap = rank01_low(overlap),
      r_saturacion = rank01_low(saturacion),
      r_subexposicion = rank01_low(subexposicion),
      r_cv_cielo = rank01_low(cv_cielo),
      r_fraccion_cielo = rank01_high(fraccion_cielo_bruto),
      
      score_qc =
        pesos["ashman"] * replace_na(r_ashman, 0.5) +
        pesos["overlap"] * replace_na(r_overlap, 0.5) +
        pesos["saturacion"] * replace_na(r_saturacion, 0.5) +
        pesos["subexposicion"] * replace_na(r_subexposicion, 0.5) +
        pesos["cv_cielo"] * replace_na(r_cv_cielo, 0.5) +
        pesos["fraccion_cielo"] * replace_na(r_fraccion_cielo, 0.5)
    ) %>%
    arrange(sitio, punto, tipo, desc(score_qc)) %>%
    mutate(
      ranking_qc = row_number(),
      n_fotos_aptas_grupo = n()
    ) %>%
    ungroup()
}

#NUEVA FUNCION
# ------------------------------------------------------------
# completar_top5_rescate()
#
# Completa el Top N de un grupo usando fotografias
# CIELO_NO_IDENTIFICABLE, unicamente cuando el grupo no alcanza
# top_k fotografias APTA. Nunca desplaza una APTA: las posiciones
# 1..n_apta_grupo del ranking siempre corresponden a APTA; el
# rescate solo ocupa las posiciones sobrantes hasta top_k.
#
# Los percentiles del rescate (rank01_high / rank01_low) se
# calculan de forma INDEPENDIENTE, solo entre las candidatas
# CIELO_NO_IDENTIFICABLE de cada grupo. Esto es intencional: no
# deben mezclarse con las APTA porque alterarian los percentiles
# ya calculados en aplicar_ranking().
# ------------------------------------------------------------
completar_top5_rescate <- function(ranking, calidad, top_k){
  
  pesos <- normalizar_pesos(PARAMS$pesos_ranking)
  
  # Conteo real de APTA por grupo, tomado de 'ranking' (ya viene
  # calculado ahi como n_fotos_aptas_grupo).
  conteo_apta <- ranking %>%
    distinct(sitio, punto, tipo, n_fotos_aptas_grupo) %>%
    rename(n_apta_grupo = n_fotos_aptas_grupo)
  
  # Todos los grupos existentes en 'calidad', para no perder de
  # vista los grupos con 0 APTA (esos no aparecen en 'ranking').
  todos_los_grupos <- calidad %>%
    distinct(sitio, punto, tipo)
  
  grupos_incompletos <- todos_los_grupos %>%
    left_join(conteo_apta, by = c("sitio", "punto", "tipo")) %>%
    mutate(
      n_apta_grupo = replace_na(n_apta_grupo, 0L),
      n_faltantes  = top_k - n_apta_grupo
    ) %>%
    filter(n_faltantes > 0)
  
  # Por defecto, todas las filas del ranking original son "NORMAL".
  ranking$origen_seleccion <- "NORMAL"
  
  if(nrow(grupos_incompletos) == 0){
    return(ranking)
  }
  
  candidatas_rescate <- calidad %>%
    filter(estado == "CIELO_NO_IDENTIFICABLE") %>%
    inner_join(
      grupos_incompletos %>%
        select(sitio, punto, tipo, n_apta_grupo, n_faltantes),
      by = c("sitio", "punto", "tipo")
    ) %>%
    anti_join(
      ranking %>%
        select(sitio, punto, tipo, archivo),
      by = c("sitio", "punto", "tipo", "archivo")
    )
  
  if(nrow(candidatas_rescate) == 0){
    return(ranking)
  }
  
  ranking_rescate <- candidatas_rescate %>%
    group_by(sitio, punto, tipo) %>%
    mutate(
      r_ashman         = rank01_high(ashmanD),
      r_overlap        = rank01_low(overlap),
      r_saturacion     = rank01_low(saturacion),
      r_subexposicion  = rank01_low(subexposicion),
      r_cv_cielo       = rank01_low(cv_cielo),
      r_fraccion_cielo = rank01_high(fraccion_cielo_bruto),
      
      score_qc =
        pesos["ashman"] * replace_na(r_ashman, 0.5) +
        pesos["overlap"] * replace_na(r_overlap, 0.5) +
        pesos["saturacion"] * replace_na(r_saturacion, 0.5) +
        pesos["subexposicion"] * replace_na(r_subexposicion, 0.5) +
        pesos["cv_cielo"] * replace_na(r_cv_cielo, 0.5) +
        pesos["fraccion_cielo"] * replace_na(r_fraccion_cielo, 0.5)
    ) %>%
    arrange(sitio, punto, tipo, desc(score_qc)) %>%
    mutate(orden_local = row_number()) %>%
    filter(orden_local <= n_faltantes) %>%
    mutate(
      ranking_qc          = n_apta_grupo + orden_local,
      n_fotos_aptas_grupo = n_apta_grupo,
      origen_seleccion    = "RESCATE"
    ) %>%
    select(-orden_local, -n_apta_grupo, -n_faltantes) %>%
    ungroup()
  
  bind_rows(ranking, ranking_rescate)
}


procesar_hemispher_fila <- function(fila){
  
  img_path <- fila$ruta_completa[[1]]
  
  message("Procesando hemispheR: ", basename(img_path))
  
  resultado <- tryCatch({
    
    img_path_hemi <- preparar_ruta_horizontal_para_mascara(img_path)
    
    img <- do.call(
      hemispheR::import_fisheye,
      crear_args_import_fisheye(img_path_hemi, PARAMS$canal_hemispher, usar_mascara = TRUE)
    )
    
    img_bin <- hemispheR::binarize_fisheye(
      img,
      method = PARAMS$metodo_binarizacion,
      zonal = PARAMS$usar_umbral_zonal,
      display = FALSE
    )
    
    gaps <- hemispheR::gapfrac_fisheye(
      img_bin,
      maxVZA = PARAMS$maxVZA,
      nrings = PARAMS$nrings,
      nseg = PARAMS$nseg,
      display = FALSE
    )
    
    hemi <- hemispheR::canopy_fisheye(gaps)
    hemi <- as.data.frame(hemi)
    
    tibble::as_tibble(hemi) %>%
      mutate(
        sitio = fila$sitio[[1]],
        punto = fila$punto[[1]],
        tipo = fila$tipo[[1]],
        archivo = fila$archivo[[1]],
        estado_hemispher = "OK",
        error_hemispher = NA_character_
      )
    
  }, error = function(e){
    
    message("ERROR hemispheR en ", basename(img_path), " | ", e$message)
    
    tibble(
      sitio = fila$sitio[[1]],
      punto = fila$punto[[1]],
      tipo = fila$tipo[[1]],
      archivo = fila$archivo[[1]],
      estado_hemispher = "ERROR_HEMISPHER",
      error_hemispher = e$message
    )
  })
  
  resultado
}

agregar_auditoria_estabilidad <- function(top_lai){
  
  if(!"L" %in% names(top_lai)) top_lai$L <- NA_real_
  if(!"DIFN" %in% names(top_lai)) top_lai$DIFN <- NA_real_
  
  top_lai %>%
    mutate(
      cobertura_dosel = ifelse(is.finite(DIFN), 100 - DIFN, NA_real_)
    ) %>%
    group_by(sitio, punto, tipo) %>%
    mutate(
      L_mediana_top = median(L, na.rm = TRUE),
      DIFN_mediana_top = median(DIFN, na.rm = TRUE),
      cobertura_mediana_top = median(cobertura_dosel, na.rm = TRUE),
      
      dif_L_pct = ifelse(
        is.finite(L) & is.finite(L_mediana_top) & L_mediana_top != 0,
        abs(L - L_mediana_top) / abs(L_mediana_top) * 100,
        NA_real_
      ),
      
      dif_DIFN_pct = ifelse(
        is.finite(DIFN) & is.finite(DIFN_mediana_top) & DIFN_mediana_top != 0,
        abs(DIFN - DIFN_mediana_top) / abs(DIFN_mediana_top) * 100,
        NA_real_
      ),
      
      dif_cobertura_puntos = ifelse(
        is.finite(cobertura_dosel) & is.finite(cobertura_mediana_top),
        abs(cobertura_dosel - cobertura_mediana_top),
        NA_real_
      ),
      
      alerta_L_inestable = ifelse(is.na(dif_L_pct), NA, dif_L_pct > PARAMS$umbral_dif_L_pct),
      alerta_DIFN_inestable = ifelse(is.na(dif_DIFN_pct), NA, dif_DIFN_pct > PARAMS$umbral_dif_DIFN_pct),
      alerta_cobertura_inestable = ifelse(
        is.na(dif_cobertura_puntos),
        NA,
        dif_cobertura_puntos > PARAMS$umbral_dif_cobertura_puntos
      ),
      
      n_top_procesado = n(),
      n_hemi_ok_grupo = sum(estado_hemispher == "OK", na.rm = TRUE),
      
      # Alertas del grupo completo. Sirven para detectar outliers dentro del top N,
      # aunque el top 1 no sea el outlier.
      grupo_alerta_L_outlier = any(replace_na(alerta_L_inestable, FALSE)),
      grupo_alerta_DIFN_outlier = any(replace_na(alerta_DIFN_inestable, FALSE)),
      grupo_alerta_cobertura_outlier = any(replace_na(alerta_cobertura_inestable, FALSE)),
      grupo_alerta_hemi_error = any(replace_na(estado_hemispher != "OK", TRUE))
    ) %>%
    ungroup()
}

crear_resumen_grupos <- function(calidad){
  
  detectados <- calidad %>%
    group_by(sitio, punto, tipo) %>%
    summarise(
      n_imagenes = n(),
      n_aptas = sum(estado == "APTA"),
      n_descartadas = sum(estado != "APTA"),
      estructura_ok = all(estructura_ok),
      .groups = "drop"
    )
  
  if(isTRUE(PARAMS$usar_grupos_esperados)){
    
    esperados <- PARAMS$grupos_esperados %>%
      as_tibble() %>%
      mutate(
        sitio = basename(normalizePath(PARAMS$ruta_imagenes, winslash = "/", mustWork = FALSE)),
        grupo_esperado = TRUE
      ) %>%
      select(sitio, punto, tipo, grupo_esperado)
    
    resumen <- esperados %>%
      full_join(detectados, by = c("sitio", "punto", "tipo")) %>%
      mutate(
        grupo_esperado = replace_na(grupo_esperado, FALSE),
        n_imagenes = replace_na(n_imagenes, 0L),
        n_aptas = replace_na(n_aptas, 0L),
        n_descartadas = replace_na(n_descartadas, 0L),
        estructura_ok = replace_na(estructura_ok, FALSE),
        grupo_presente = n_imagenes > 0,
        alerta_grupo_faltante = grupo_esperado & !grupo_presente,
        alerta_numero_fotos = grupo_esperado & grupo_presente &
          n_imagenes != PARAMS$fotos_esperadas_por_grupo
      ) %>%
      arrange(punto, tipo)
    
  } else {
    
    resumen <- detectados %>%
      mutate(
        grupo_esperado = NA,
        grupo_presente = n_imagenes > 0,
        alerta_grupo_faltante = FALSE,
        alerta_numero_fotos = n_imagenes != PARAMS$fotos_esperadas_por_grupo
      )
  }
  
  resumen
}

crear_justificacion_v2 <- function(
    decision,
    flag_sat_revision,
    flag_subexp_revision,
    flag_cv,
    flag_ashman,
    flag_overlap,
    alerta_L_top1,
    alerta_DIFN_top1,
    alerta_cobertura_top1,
    alerta_score,
    error_hemi,
    grupo_alerta_L,
    grupo_alerta_DIFN,
    grupo_alerta_cobertura,
    grupo_alerta_hemi
){
  
  motivos <- c()
  
  if(isTRUE(flag_sat_revision)) motivos <- c(motivos, "saturacion moderada/alta")
  if(isTRUE(flag_subexp_revision)) motivos <- c(motivos, "subexposicion muy alta")
  if(isTRUE(flag_cv)) motivos <- c(motivos, "CV del cielo alto")
  if(isTRUE(flag_ashman)) motivos <- c(motivos, "Ashman's D bajo")
  if(isTRUE(flag_overlap)) motivos <- c(motivos, "overlap alto")
  if(isTRUE(alerta_L_top1)) motivos <- c(motivos, "LAI del top 1 inestable frente al top de candidatas")
  if(isTRUE(alerta_DIFN_top1)) motivos <- c(motivos, "DIFN del top 1 inestable frente al top de candidatas")
  if(isTRUE(alerta_cobertura_top1)) motivos <- c(motivos, "cobertura del top 1 inestable frente al top de candidatas")
  if(isTRUE(alerta_score)) motivos <- c(motivos, "margen bajo entre top 1 y top 2")
  if(isTRUE(error_hemi)) motivos <- c(motivos, "error en calculo hemispheR del top 1")
  if(isTRUE(grupo_alerta_L)) motivos <- c(motivos, "outlier de LAI dentro del top de candidatas")
  if(isTRUE(grupo_alerta_DIFN)) motivos <- c(motivos, "outlier de DIFN dentro del top de candidatas")
  if(isTRUE(grupo_alerta_cobertura)) motivos <- c(motivos, "outlier de cobertura dentro del top de candidatas")
  if(isTRUE(grupo_alerta_hemi)) motivos <- c(motivos, "al menos una candidata del grupo fallo en hemispheR")
  
  if(length(motivos) == 0){
    return("Seleccion automatica aceptada: top 1 por ranking, estable y sin alertas principales")
  }
  
  paste0(decision, ": ", paste(unique(motivos), collapse = "; "))
}

seleccionar_foto_final <- function(auditoria){
  
  auditoria %>%
    group_by(sitio, punto, tipo) %>%
    arrange(ranking_qc, .by_group = TRUE) %>%
    mutate(
      score_top1 = first(score_qc),
      score_top2 = nth(score_qc, 2, default = NA_real_),
      margen_score_top1_top2 = score_top1 - score_top2
    ) %>%
    filter(ranking_qc == 1) %>%
    ungroup() %>%
    mutate(
      alerta_score_cercano = ifelse(
        is.na(margen_score_top1_top2),
        FALSE,
        margen_score_top1_top2 < PARAMS$margen_score_min
      ),
      error_hemi = replace_na(estado_hemispher != "OK", TRUE),
      
      # Revision obligatoria: problemas del top 1 o errores que comprometen la decision.
      revision_obligatoria =
        replace_na(flag_ashman_bajo, FALSE) |
        replace_na(flag_overlap_alto, FALSE) |
        replace_na(alerta_L_inestable, FALSE) |
        replace_na(alerta_DIFN_inestable, FALSE) |
        replace_na(alerta_cobertura_inestable, FALSE) |
        replace_na(error_hemi, TRUE),
      
      # Revision visual rapida: la seleccion parece usable, pero debe confirmarse visualmente.
      revision_visual_rapida =
        replace_na(flag_saturacion_revision, FALSE) |
        replace_na(flag_subexposicion_revision, FALSE) |
        replace_na(flag_cv_cielo, FALSE) |
        replace_na(alerta_score_cercano, FALSE) |
        replace_na(grupo_alerta_L_outlier, FALSE) |
        replace_na(grupo_alerta_DIFN_outlier, FALSE) |
        replace_na(grupo_alerta_cobertura_outlier, FALSE) |
        replace_na(grupo_alerta_hemi_error, FALSE),
      
      decision = case_when(
        revision_obligatoria ~ "REVISION_MANUAL_OBLIGATORIA",
        revision_visual_rapida ~ "REVISION_VISUAL_RAPIDA",
        TRUE ~ "SELECCION_AUTOMATICA"
      )
    ) %>%
    rowwise() %>%
    mutate(
      justificacion = crear_justificacion_v2(
        decision = decision,
        flag_sat_revision = flag_saturacion_revision,
        flag_subexp_revision = flag_subexposicion_revision,
        flag_cv = flag_cv_cielo,
        flag_ashman = flag_ashman_bajo,
        flag_overlap = flag_overlap_alto,
        alerta_L_top1 = alerta_L_inestable,
        alerta_DIFN_top1 = alerta_DIFN_inestable,
        alerta_cobertura_top1 = alerta_cobertura_inestable,
        alerta_score = alerta_score_cercano,
        error_hemi = error_hemi,
        grupo_alerta_L = grupo_alerta_L_outlier,
        grupo_alerta_DIFN = grupo_alerta_DIFN_outlier,
        grupo_alerta_cobertura = grupo_alerta_cobertura_outlier,
        grupo_alerta_hemi = grupo_alerta_hemi_error
      )
    ) %>%
    ungroup()
}

crear_resumen_seleccion <- function(seleccion_final){
  seleccion_final %>%
    transmute(
      sitio,
      punto,
      tipo,
      archivo_seleccionado = archivo,
      decision,
      justificacion,
      ranking_qc,
      score_qc,
      score_top2,
      margen_score_top1_top2,
      saturacion,
      subexposicion,
      ashmanD,
      overlap,
      cv_cielo,
      fraccion_cielo_bruto,
      L,
      DIFN,
      cobertura_dosel,
      grupo_alerta_L_outlier,
      grupo_alerta_DIFN_outlier,
      grupo_alerta_cobertura_outlier
    )
}

# ============================================================
# 03. EJECUCION DEL FLUJO
# ============================================================

message("Ruta de imagenes: ", PARAMS$ruta_imagenes)
message("Carpeta de salida: ", DIR_SALIDA)

imagenes <- list.files(
  path = PARAMS$ruta_imagenes,
  recursive = TRUE,
  full.names = TRUE,
  pattern = PARAMS$extensiones_imagen,
  ignore.case = TRUE
)

# Evita releer graficos o archivos generados dentro de la carpeta de salida.
imagenes_norm <- normalizePath(imagenes, winslash = "/", mustWork = FALSE)
patron_salida <- paste0("/", PARAMS$carpeta_salida, "(/|$)")
imagenes <- imagenes[!grepl(patron_salida, imagenes_norm)]

if(length(imagenes) == 0){
  stop("No se encontraron imagenes en la ruta indicada.")
}

message("Imagenes encontradas: ", length(imagenes))

# ------------------------------------------------------------
# 03.1 Control de calidad de todas las fotos
# ------------------------------------------------------------

calidad <- purrr::map_df(seq_along(imagenes), function(i){
  message("[", i, "/", length(imagenes), "] ", basename(imagenes[i]))
  procesar_calidad_imagen(imagenes[i])
})

resumen_grupos <- crear_resumen_grupos(calidad)

escribir_tabla(resumen_grupos, "00_resumen_grupos.csv")
escribir_tabla(calidad, "01_calidad_fotos.csv")

# ------------------------------------------------------------
# 03.2 Ranking multicriterio dentro de cada sitio/parcela/altura
# ------------------------------------------------------------

ranking <- aplicar_ranking(calidad)

if(nrow(ranking) == 0){
  stop("No hay fotografias APTAS para rankear. Revisar filtros de calidad.")
}

ranking <- completar_top5_rescate(
  ranking = ranking,
  calidad = calidad,
  top_k = PARAMS$top_k
)

escribir_tabla(ranking, "02_ranking_fotos.csv")

# ------------------------------------------------------------
# 03.3 Top N candidatas por grupo y calculo con hemispheR
# ------------------------------------------------------------

top_candidatas <- ranking %>%
  filter(ranking_qc <= PARAMS$top_k)

resultados_hemi <- purrr::map_df(seq_len(nrow(top_candidatas)), function(i){
  procesar_hemispher_fila(top_candidatas[i, ])
})

top_lai <- top_candidatas %>%
  left_join(
    resultados_hemi,
    by = c("sitio", "punto", "tipo", "archivo")
  )

# ------------------------------------------------------------
# 03.4 Auditoria de estabilidad del top N
# ------------------------------------------------------------

auditoria <- agregar_auditoria_estabilidad(top_lai)

escribir_tabla(auditoria, "03_top_candidatas_LAI_auditoria.csv")

# ------------------------------------------------------------
# 03.5 Seleccion final por grupo
# ------------------------------------------------------------

seleccion_final <- seleccionar_foto_final(auditoria)
resumen_seleccion <- crear_resumen_seleccion(seleccion_final)

escribir_tabla(seleccion_final, "04_seleccion_final.csv")
escribir_tabla(resumen_seleccion, "05_resumen_seleccion_final.csv")

message("Proceso finalizado.")
message("Archivos principales:")
message("  00_resumen_grupos.csv")
message("  01_calidad_fotos.csv")
message("  02_ranking_fotos.csv")
message("  03_top_candidatas_LAI_auditoria.csv")
message("  04_seleccion_final.csv")
message("  05_resumen_seleccion_final.csv")

# ============================================================
# FIN DEL SCRIPT
# ============================================================

