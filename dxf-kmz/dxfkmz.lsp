;;; DXFKMZ.LSP - Dibujo (o seleccion) -> KMZ para Google Earth.   BricsCAD y AutoCAD.
;;; Carga: APPLOAD -> %LOCALAPPDATA%\DxfKmz\dxfkmz.lsp (o C:\DxfKmz\dxfkmz.lsp).   Comando: DXFKMZ
;;; Pide los objetos (Enter = todo el dibujo) y la zona UTM; deja <dibujo>_GE.kmz junto al DWG.
;;; El dibujo debe estar en coordenadas UTM reales (metros).
(vl-load-com)
;; Carpeta de instalacion: primero la del usuario (sin permisos de administrador), luego C:\DxfKmz
(setq *dxfkmz-dir*
  (cond
    ((and (getenv "LOCALAPPDATA")
          (findfile (strcat (vl-string-translate "\\" "/" (getenv "LOCALAPPDATA")) "/DxfKmz/dxfkmz.bat")))
     (strcat (vl-string-translate "\\" "/" (getenv "LOCALAPPDATA")) "/DxfKmz/"))
    (T "C:/DxfKmz/")))

;; (aci color-verdadero apagada) de una capa
(defun dxfkmz:capa (nombre / d)
  (setq d (tblsearch "LAYER" nombre))
  (list (abs (cdr (assoc 62 d)))
        (cdr (assoc 420 d))
        (or (< (cdr (assoc 62 d)) 0) (= 1 (logand 1 (cdr (assoc 70 d)))))))

;; "aci<TAB>color-verdadero" ya resuelto (entidad, o capa si es PorCapa/PorBloque)
(defun dxfkmz:color (ed li / aci tc)
  (setq aci (cdr (assoc 62 ed))
        tc  (cdr (assoc 420 ed)))
  (cond
    (tc (strcat "7\t" (itoa tc)))
    ((and aci (> aci 0) (< aci 256)) (strcat (itoa aci) "\t"))
    (T (strcat (itoa (car li)) "\t" (if (cadr li) (itoa (cadr li)) "")))))

(defun dxfkmz:pt (p)
  (strcat (rtos (car p) 2 3) " " (rtos (cadr p) 2 3)))

(defun dxfkmz:unir (lst sep / s)
  (setq s (car lst))
  (foreach x (cdr lst) (setq s (strcat s sep x)))
  s)

(defun dxfkmz:limpiar (s)
  (vl-string-translate "\t\n\r" "   " s))

;; puntos que describen la curva (arcos de polilinea y curvas se subdividen)
(defun dxfkmz:muestras (obj tipo / p0 p1 i n pts a b m)
  (setq p0 (vlax-curve-getStartParam obj)
        p1 (vlax-curve-getEndParam obj))
  (cond
    ((= tipo "LINE")
     (setq pts (list (vlax-curve-getStartPoint obj) (vlax-curve-getEndPoint obj))))
    ((member tipo '("LWPOLYLINE" "POLYLINE"))
     (setq i (fix p0))
     (while (< i (fix p1))
       (setq a (vlax-curve-getPointAtParam obj i)
             b (vlax-curve-getPointAtParam obj (1+ i))
             m (vlax-curve-getPointAtParam obj (+ i 0.5))
             pts (cons a pts))
       (if (> (distance m (mapcar '(lambda (u v) (/ (+ u v) 2.0)) a b)) 0.001) ; tramo con bulge
         (progn
           (setq n 1)
           (repeat 15
             (setq pts (cons (vlax-curve-getPointAtParam obj (+ i (/ n 16.0))) pts)
                   n (1+ n)))))
       (setq i (1+ i)))
     (setq pts (reverse (cons (vlax-curve-getEndPoint obj) pts))))
    (T ; ARC CIRCLE ELLIPSE SPLINE
     (setq i 0)
     (repeat 65
       (setq pts (cons (vlax-curve-getPointAtParam obj (+ p0 (* (- p1 p0) (/ i 64.0)))) pts)
             i (1+ i)))
     (setq pts (reverse pts))))
  pts)

;; escribe un objeto en el archivo; devuelve 1 si lo escribio
(defun dxfkmz:objeto (f ent / ed tipo capa li col obj pts cerrado nom)
  (setq ed   (entget ent)
        tipo (cdr (assoc 0 ed))
        capa (cdr (assoc 8 ed))
        li   (dxfkmz:capa capa))
  (if (caddr li)
    0
    (progn
      (setq col (dxfkmz:color ed li))
      (cond
        ((= tipo "POINT")
         (write-line (strcat "P\t" capa "\t" col "\t" (dxfkmz:pt (cdr (assoc 10 ed))) "\t") f)
         1)
        ((= tipo "INSERT")
         (setq nom (cdr (assoc 2 ed)))
         (write-line (strcat "P\t" capa "\t" col "\t" (dxfkmz:pt (cdr (assoc 10 ed))) "\t"
                             (if (= (substr nom 1 1) "*") "" nom)) f)
         1)
        ((member tipo '("TEXT" "MTEXT"))
         (write-line (strcat "T\t" capa "\t" col "\t" (dxfkmz:pt (cdr (assoc 10 ed))) "\t"
                             (dxfkmz:limpiar (cdr (assoc 1 ed)))) f)
         1)
        ((member tipo '("LINE" "LWPOLYLINE" "POLYLINE" "ARC" "CIRCLE" "ELLIPSE" "SPLINE"))
         (setq obj (vlax-ename->vla-object ent)
               pts (vl-catch-all-apply 'dxfkmz:muestras (list obj tipo)))
         (if (and pts (not (vl-catch-all-error-p pts)) (> (length pts) 1))
           (progn
             (setq cerrado (and (/= tipo "LINE") (= (vlax-curve-isClosed obj) :vlax-true)))
             (if (and cerrado (equal (car pts) (last pts) 1e-6))
               (setq pts (reverse (cdr (reverse pts)))))
             (write-line (strcat (if cerrado "G" "L") "\t" capa "\t" col "\t"
                                 (dxfkmz:unir (mapcar 'dxfkmz:pt pts) ";"))
                         f)
             1)
           0))
        (T 0)))))

(defun c:DXFKMZ ( / bat ss i n f tmp kmz log sh cmd rc ult resp errant)
  (setq bat (strcat *dxfkmz-dir* "dxfkmz.bat"))
  (cond
    ((not (findfile bat))
     (princ (strcat "\nNo se encuentra " bat " (editar *dxfkmz-dir* al inicio de dxfkmz.lsp)")))
    (T
     (princ "\nSeleccione los objetos a exportar (Enter = todo el dibujo): ")
     (setq ss (ssget))
     (if (null ss) (setq ss (ssget "_X" (list (cons 410 "Model")))))
     (if (null ss)
       (princ "\nNo hay objetos.")
       (progn
         (setq ult (if (getenv "DXFKMZ_EPSG") (getenv "DXFKMZ_EPSG") "32718")
               resp (getstring (strcat "\nZona UTM (17, 18, 19 = sur; 18N = norte) o codigo EPSG <" ult ">: ")))
         (if (= resp "") (setq resp ult))
         (cond
           ((not (wcmatch (strcase resp) "#,##,####,#####,#N,##N,#S,##S"))
            (princ (strcat "\nZona no valida: " resp)))
           (T
            (setenv "DXFKMZ_EPSG" resp)
            (setq tmp (strcat (getenv "TEMP") "\\dxfkmz_objetos.txt")
                  log (strcat (getenv "TEMP") "\\dxfkmz_log.txt")
                  kmz (strcat (getvar "DWGPREFIX") (vl-filename-base (getvar "DWGNAME")) "_GE.kmz")
                  f (open tmp "w")
                  n 0 i 0)
            (write-line (strcat "U\t" (itoa (getvar "INSUNITS"))) f)
            (repeat (sslength ss)
              (setq n (+ n (dxfkmz:objeto f (ssname ss i)))
                    i (1+ i)))
            (close f)
            (princ (strcat "\n" (itoa n) " objetos exportados. Convirtiendo..."))
            (if (findfile kmz) (vl-file-delete kmz))
            (setq sh  (vlax-create-object "WScript.Shell")
                  cmd (strcat "cmd /c \"\"" (vl-string-translate "/" "\\" bat) "\" /nopausa --lisp \"" tmp
                              "\" -o \"" kmz "\" --epsg " resp " > \"" log "\" 2>&1\"")
                  rc  (vlax-invoke-method sh 'Run cmd 0 :vlax-true))
            (vlax-release-object sh)
            (if (setq f (open log "r"))
              (progn
                (while (setq cmd (read-line f)) (princ (strcat "\n" cmd)))
                (close f)))
            (vl-file-delete tmp)
            (if (findfile kmz)
              (progn
                (princ (strcat "\nListo: " kmz))
                (startapp "explorer.exe" (strcat "/select,\"" kmz "\"")))
              (princ "\nNo se genero el KMZ (ver mensaje de arriba)."))))))))
  (princ))

(princ "\nDXFKMZ cargado: escribir DXFKMZ para exportar a KMZ (Google Earth).")
(princ)
