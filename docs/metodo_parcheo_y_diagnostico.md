# Método de parcheo y diagnóstico — KOF XI Atomiswave

> Cómo trabajamos el ejecutable `ax3201p01.fmem1.dec` (8 MB, flash descifrado):
> identificar cambios, parchear con seguridad, y **diagnosticar en vivo con el Lua**
> en vez de re-flashear a ciegas. Última actualización: 2026-06-22.
>
> Estado honesto: hornear parches en el ROM salió "más o menos" — sigue habiendo
> rarezas. Por eso el método ahora **prioriza el Lua** (testeo en vivo, no destructivo)
> para aislar la causa antes de tocar el binario.

---

## 0. Modelo mental (memorízalo)

```
Archivo .dec  = [header "System X" 0x100 bytes] + [programa SH-4]
Carga en RAM  = 0x8C010000   (cacheado; mirror sin caché 0x0C000000)

Conversiones de offset:
  body   = AW_file - 0x100
  RAM    = 0x8C010000 + body              = AW_file - 0x100 + 0x8C010000
  RAW    = body + 0x10000                 (offset que usa el Lua: BASE 0x0C000000 + RAW)
  AW_file= RAW - 0x10000 + 0x100
```

El header NO tiene checksum del cuerpo (solo metadatos: `0x60`=offset 0x100,
`0x64`=load 0x8C010000, `0x68`=size 0x122820, `0x6C`=entry). → parchear el cuerpo
no obliga a recalcular nada.

---

## 1. Identificar cambios (diff entre dumps)

Cuando sospechas que un dump trae cambios, **diferéncialo contra una base** y mira los
runs de bytes distintos:

```python
a = open("dump_A","rb").read(); b = open("dump_B","rb").read()
diffs = [i for i in range(min(len(a),len(b))) if a[i]!=b[i]]
# agrupar en runs y volcar hex de cada lado
```

**Cómo reconocer "factory" vs "parche":**
- `mov #const,R0 ; rts ; nop`  (bytes `XX E0 0B 00 09 00`) = **stub que fuerza un valor de
  retorno**. Es un PARCHE. (`E0xx`=mov #imm,R0; `000B`=rts; `0009`=nop.)
- Un prólogo de función real empieza t��picamente con `4F 22` (`sts.l PR,@-R15`) seguido de
  `7F xx` (`add #-n,R15`). Eso es CÓDIGO ORIGINAL.
- `09 00` (nop) donde antes había un `or`/`mov` = parche puntual (p.ej. el bilineal).

> Caso real (2026-06-22): el `_backup` "recién extraído" resultó ser el SUCIO. Diff vs
> `_original` = 14 bytes en 3 sitios del motor de personajes, todos stubs de "forzar
> retorno". Es decir: el origen del que extrajiste el backup ya estaba modificado.

**Limitación:** un diff entre A y B no ve un cambio que **ambos comparten**. Sin un dump de
fábrica con CRC conocido no puedes descartar mods compartidos. Por eso el siguiente paso es
el diagnóstico en vivo (sección 4): no depende de tener una base 100% limpia.

---

## 2. Confirmar qué hace un cambio (desensamblado)

Hay un desensamblador SH-4 mínimo en `/tmp/sh4dis.py` (generado en estas sesiones).
Para leer una rutina, alinéala con `base=0x8c010000, file_base=0x100` (archivo AW):

```python
import sys; sys.path.insert(0,'/tmp'); import sh4dis
data = open("ax3201p01.fmem1.dec_original","rb").read()
print(sh4dis.run(data, 0x06C94C, 0x20, base=0x8c010000, file_base=0x100))
```

Opcodes clave para este juego:
- `or Rm,Rn` = `0x2__B` → arma bits del filtro PVR (bilineal).
- `mov.w @(d,PC),Rn` = `0x9__` → carga constante de la *literal pool* (sigue el `;=0x….`).
- `mov #imm,Rn` = `0xE___`, `rts`=`0x000B`, `nop`=`0x0009`.

---

## 3. Parchear el binario con seguridad — `patch_kofxi_aw.py`

Script con sitios conocidos (factory/patched) y **aborto si algo no calza** (no corrompe):

```
python3 patch_kofxi_aw.py verify   IN          # estado de los 6 sitios
python3 patch_kofxi_aw.py clean    IN OUT      # char-engine -> factory
python3 patch_kofxi_aw.py bilinear IN OUT      # bilineal off
python3 patch_kofxi_aw.py all      IN OUT      # clean + bilinear (recomendado)
```

Para añadir un sitio nuevo: mete una tupla `(offset, factory_bytes, patched_bytes, desc)`
en `BILINEAR` o `CHAR`. El script clasifica cada sitio leyendo sus bytes actuales.

Hashes de referencia (md5):
- `_original` (limpio) ........ `3db3ab60f0f2790fac044ecd89db8944`
- `_bilinear` = `clean+bilinear` `af00dbde68b3b1eb2f6dcae4580e3d25`
- `_backup` (sucio) ........... `61e1f3ef6b4e681e8d59b0338d70d6fe`

---

## 4. Diagnóstico EN VIVO con el Lua (la vía recomendada)

El programa corre desde RAM, así que el Lua de training puede **leer y reescribir el código
en caliente** — togglear parches sin re-flashear. Esto vive en
`kofxi_training_lua/kofxi_training/extras/` (`extras.lua` + `extras_overlay.lua`), cableado
en `kofxi.lua` antes del gate de `in_match()` (funciona también en menús).

Ventana **"Extras"** (esquina arriba-izq.):

| Control | Qué hace |
|---|---|
| **Bilinear: ON/OFF** | nop/restaura los 3 `or` del filtro (RAW `0x010522/0x0B9084/0x0B9108`). |
| **Char-engine (live A/B)** | por cada sitio (`@7C854/@7EE94/@8109C`): muestra `factory/patched/unknown` leído en vivo y cicla **observe → factory → patched**. |
| **All -> FACTORY / observe** | fuerza los 3 a factory de golpe, o suelta el forzado. |
| **menu_state / cursor / Menu log** | explorador del menú debug (sección 5 del estudio). |

### Receta para cazar "personajes raros"
1. Carga el juego como lo tienes ahora y entra a un combate.
2. En la ventana Extras mira el estado de los 3 sitios char-engine:
   - si dicen **patched** → tu ROM cargado trae los stubs.
3. Pulsa **All -> FACTORY** y observa: ¿se normalizan los personajes?
   - **Sí** → la causa eran esos 3 parches; usa `patch_kofxi_aw.py clean/all` para hornearlo.
   - **No** → la causa NO son esos 3 (o no solo). Sigue con el paso 4.
4. Aísla: deja 2 en observe y cicla **uno** a `patched`/`factory` para ver cuál mueve la aguja.
   Como todo es RAM, un reset deshace cualquier cosa.
5. Si nada de esto lo explica, el problema probablemente está **compartido por ambos dumps**
   (mod previo no detectable por diff) o en **SRAM/config** (ver `hallazgos_track04_sram.md`),
   o en el **re-encriptado/repack** al volver el `.dec` al emulador. Descártalos por separado:
   prueba el `_original` crudo sin tu pipeline de repack, y una SRAM por defecto.

> Nota: los flags del menú debug (`0x126DF8+`) son internos del menú y NO afectan al gameplay;
> para cheats reales usa los toggles de training (Inf Health, etc.).

---

## 5. Flujo recomendado (resumen)

```
1. diff contra base           -> localizar cambios candidatos        (sección 1)
2. sh4dis                     -> entender qué hace cada cambio        (sección 2)
3. Lua: togglear en vivo      -> CONFIRMAR causa sin re-flashear      (sección 4)  <- clave
4. patch_kofxi_aw.py          -> hornear SOLO lo confirmado           (sección 3)
5. verify + md5               -> dejar trazabilidad
```

La regla: **confirma en RAM con el Lua antes de tocar el ROM.** Hornear a ciegas es lo que
salió "más o menos".

---

## 6. Archivos relacionados
- `patch_kofxi_aw.py` — verificador/parcheador del binario.
- `kofxi_training_lua/kofxi_training/extras/` — toggles en vivo (bilineal + char-engine A/B).
- `hallazgos_track04_sram.md` — track04 ↔ ejecutable, y la SRAM.
- `estudio_bilinear_y_menus_ocultos.md` — bilineal a fondo + menús ocultos.
- `ejecutable_alternativo_CHANGELOG.md` — builds generados + análisis del `_backup`.
