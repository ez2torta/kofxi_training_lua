# Ejecutable alternativo Atomiswave — `ax3201p01.fmem1.dec_bilinear`

> Build derivado de `ax3201p01.fmem1.dec_original` (KOF XI Atomiswave, "System X",
> build interno `20051025`). Documenta **qué se cambió, por qué, y qué NO se pudo hacer de
> forma segura**. Fecha: 2026-06-21.
> Ver también: [`hallazgos_track04_sram.md`](hallazgos_track04_sram.md) y
> [`estudio_bilinear_y_menus_ocultos.md`](estudio_bilinear_y_menus_ocultos.md).

| | |
|---|---|
| Archivo origen | `ax3201p01.fmem1.dec_original` (8,388,608 bytes, md5 `3db3ab60f0f2790fac044ecd89db8944`) |
| Archivo nuevo  | `ax3201p01.fmem1.dec_bilinear` (8,388,608 bytes, md5 `af00dbde68b3b1eb2f6dcae4580e3d25`) |
| Bytes cambiados | **6** (3 instrucciones) |
| Header tocado | **No** (0x00–0x100 intacto) |
| Tamaño | Idéntico |

---

## 1. Cambio aplicado: parche de bilineal (HORNEADO ✅)

Se desactiva el filtrado bilineal de texturas (deja la imagen en *point sampling*, píxeles
nítidos). Es el mismo parche que ya tenías en `track04_modificado.iso` (versión Dreamcast),
trasladado a la versión **Atomiswave** — los 3 sitios existen idénticos en ambos binarios, con
un offset de +0x100 (el header de arcade).

### 1.1 Diff exacto

| Offset (AW) | RAM | Antes | Después | Instrucción | Rol |
|---|---|---|---|---|---|
| `0x000622` | `0x8C010522` | `4B 20` | `09 00` | `or R4,R0` → `nop` | **Setter global de filtro** |
| `0x0A9184` | `0x8C0B9084` | `1B 20` | `09 00` | `or R1,R0` → `nop` | Ruta de polígono, bit `0x2000` |
| `0x0A9208` | `0x8C0B9108` | `2B 21` | `09 00` | `or R2,R1` → `nop` | Ruta de polígono, bit `0x4000` |

### 1.2 Justificación técnica

- **Qué hacen esas instrucciones.** El juego arma una palabra de atributos de render (el
  *TSP Instruction Word* del PowerVR2). Los bits 12–15 de esa palabra son el modo de filtrado
  de textura. El código primero **limpia** esos bits (`and 0xEFFF`, `and 0x9FFF`) y luego los
  **vuelve a poner** con `or 0x2000` / `or 0x4000` cuando quiere filtrar. El sitio `0x622` es el
  *setter* central: hace `campo &= 0x9FFF; campo |= R4` sobre el contexto de render global
  (`*(0x8C13D7CC)`). Al volver `nop` los `or`, los bits de filtro quedan en 0 → **point
  sampling**. (Análisis completo en `estudio_bilinear_y_menus_ocultos.md`.)

- **Por qué estos 3 y no otros.** Es exactamente tu patch ya probado para Dreamcast. Hay ~100
  sitios candidatos más (sobre todo el motor de sprites 2D en `0x5F000–0x64000`), pero el setter
  global cubre la mayoría del render. Si tras probar notas sprites aún suavizados, ese cluster es
  el siguiente paso (documentado, pero **no** incluido aquí por no estar verificado).

- **Por qué es seguro.**
  1. Solo cambia 3 palabras de código por `nop`; no mueve nada, no cambia tamaños ni offsets.
  2. El header "System X" (0x00–0x100) **no contiene checksum del cuerpo** — solo metadatos de
     carga (`0x60`=offset 0x100, `0x64`=load 0x8C010000, `0x68`=size 0x122820, `0x6C`=entry).
     Verificado: ninguna suma/CRC del cuerpo aparece en el header. → No hay que recalcular nada.
  3. `nop` (`0x0009`) es una instrucción legal de relleno; no altera el flujo ni la pila.

### 1.3 Cómo usarlo

`*.dec` es la región de flash **descifrada**. Para correrlo, pásalo por el **mismo pipeline con
el que obtuviste el `.dec`** (re-encriptado / carga directa de flash descifrada, según tu
emulador AW — Demul/Flycast/MAME). El parche en sí no añade requisitos nuevos: como el header no
lleva checksum, el binario parcheado es un reemplazo directo del original en ese flujo.

---

## 2. Menú DEBUG de desarrollador — análisis de viabilidad (NO horneado ⚠️)

**¿Es posible? Sí, el menú existe y está 100% funcional en el código. Pero activarlo por parche
ciego en el ROM no es algo que pueda garantizar sin probarlo en emulador**, y un parche mal
puesto deja el arranque en negro. Por eso **no lo metí en el archivo principal**. Aquí va todo lo
necesario para activarlo de forma verificada.

### 2.1 Qué encontré (mapa completo)

| Elemento | Dirección |
|---|---|
| Tabla del menú debug (26 entradas `{flag, label}`) | `RAM 0x8C05D170` (AW `0x4D270`) |
| Handler (dibuja el menú) | `RAM 0x8C05C9C8` (AW `0x4C9C8`) |
| Llamador del handler | `RAM 0x8C05CCB8` |
| Variables/flags de debug | `RAM 0x8C126DF8` y sig. (paso `0x10`) |
| Variable de **estado** del menú | `RAM 0x8C189128` |
| Variable de **cursor** | `RAM 0x8C18926C` |
| Tabla cursor→acción | `RAM 0x8C126DE8` |

Entradas del menú: `MUTEKI` (無敵 = invencible), `No Life`, `Death`, `Undead`, `Time Stop`,
`Time Down`, `Time Over`, `Wait`, `Pause`, `Still`, `CP`, y 15 más.

### 2.2 Por qué NO lo horneé (la parte honesta)

1. **Es un "estado" de una máquina de estados de menú multinivel**, no una simple entrada con un
   contador como el menú Time Release del artículo. El handler se alcanza vía
   `dispatcher (0x8C05BEC8) → estado (0x8C189128) → sub-handlers → bsr 0x8C05C9C4`. La
   transición exacta que lleva al estado "debug" depende de valores que se fijan en runtime; sin
   un debugger no puedo asegurar qué byte/condición forzar.

2. **Los flags de debug son internos del menú.** Verifiqué que `0x8C126DF8` (MUTEKI) **solo lo
   referencia el código del menú** — el gameplay no lo lee directo. Es decir: poner `MUTEKI=1`
   por cheat de RAM **no** da invencibilidad por sí solo; el efecto lo aplica la lógica del menú
   cuando está activo. Activar de verdad requiere que el menú/su lógica corran.

3. **No puedo ejecutar el juego aquí** para validar. Hornear un salto/condición sin probar = alto
   riesgo de romper el boot.

### 2.3 Cómo activarlo TÚ (verificado en emulador) — receta

Hazlo en **Demul / Flycast / MAME** (modo Atomiswave) con visor de memoria + breakpoints:

1. **Localiza la transición de estado.** Pon un *write breakpoint* en `0x8C189128` (estado del
   menú) y `0x8C18926C` (cursor). Entra al Test Menu y navega; observa qué valor de estado
   coincide con que se llame al handler `0x8C05C9C8` (pon también un *exec breakpoint* ahí).
2. **Fuerza el estado.** Una vez sepas el valor de estado que activa el debug, prueba escribirlo
   a mano en `0x8C189128` desde el menú — debería entrar al menú debug. (No destructivo, todo en
   RAM.)
3. **Cuando funcione, hornéalo.** Recién entonces parchea en el ROM la condición que mapea una
   entrada de menú visible → ese estado (o sube el contador del menú padre, estilo Time Release).
   Como ya lo probaste, sabrás el byte exacto y el riesgo es mínimo.

> Si me confirmas (con el emulador abierto) qué valor toma `0x8C189128` al entrar al menú debug,
> te calculo el parche de ROM exacto para dejarlo accesible de forma permanente.

### 2.4 Atajo para CHEATS reales (sin el menú)

Si lo que quieres es **invencibilidad** y no el menú en sí, el camino correcto no es `0x8C126DF8`
sino la **estructura del jugador** (HP/daño), que ya tienes documentada en tu repo
(`docs/uni_ram_analysis.md` y el "Player Struct Memory Map"). Un cheat sobre el HP del jugador es
directo y verificable, e independiente del menú debug.

---

## 2b. Análisis del `_backup` (2026-06-22) — ¡los parches estaban en el backup!

Sospechabas que tu `_original` traía cambios y que `_backup` (recién extraído) era limpio.
**Es al revés.** Diff `_backup` vs `_original` = solo **14 bytes en 3 sitios**, todos en el
motor de personajes/animación (`~0x6C000–0x71000`), y el `_backup` es el que los tiene:

| Offset (AW) | `_original` (factory) | `_backup` (parcheado) | Qué hace el parche |
|---|---|---|---|
| `0x06C954` | `22 4F F0 7F 43 1F` (prólogo de función) | `01 E0 0B 00 09 00` | función → `mov #1; rts` (devuelve **1**) |
| `0x06EF94` | `22 4F EC 7F F3 63` (prólogo de función) | `FF E0 0B 00 09 00` | función → `mov #0xFF; rts` (devuelve **0xFF**) |
| `0x07119C` | `01 60` = `mov.w @R0,R0` | `05 E0` = `mov #5,R0` | lectura de valor → **constante 5** |

Son hacks clásicos de "forzar valor de retorno" en el motor de personajes → causa muy probable
de que **"los personajes hagan cosas raras"**. El bilineal está intacto en ambos.

**Verificado por hashes:**
- `clean(_backup)` (restaurar esos 3 sitios) → **md5 `3db3ab…` = idéntico a `_original`** ⇒ tu
  `_original` SÍ es la base limpia.
- `all(_backup)` (clean + bilinear) → **md5 `af00db…` = idéntico a `ax3201p01.fmem1.dec_bilinear`**.

> Caveat honesto: esto compara `_backup` contra `_original`. Si `_original` arrastrara algún
> cambio que **ambos** comparten, un diff entre ellos no lo vería (no tengo un dump de fábrica de
> referencia con CRC conocido). Pero como tu problema aparece con el `_backup` y este solo difiere
> en esos 3 sitios, restaurarlos es la solución dirigida. Prueba con la base limpia y confirma.

### Script: `patch_kofxi_aw.py`

```
python3 patch_kofxi_aw.py verify   ENTRADA          # reporta estado de los 6 sitios
python3 patch_kofxi_aw.py clean    ENTRADA SALIDA   # restaura char-engine a factory
python3 patch_kofxi_aw.py bilinear ENTRADA SALIDA   # aplica bilineal-off
python3 patch_kofxi_aw.py all      ENTRADA SALIDA   # clean + bilinear (recomendado)
```

Cada sitio solo se escribe si su contenido actual coincide con una forma conocida (factory o
patched); si algo no calza, **aborta sin escribir** (no corrompe). Archivo generado:
**`ax3201p01.fmem1.dec_clean_bilinear`** (char-engine limpio + bilineal off).

## 3. Resumen

| Objetivo | Estado | Dónde |
|---|---|---|
| Bilineal off (point sampling) | ✅ **Horneado y verificado** | `ax3201p01.fmem1.dec_bilinear` |
| Menú debug accesible | ⚠️ **Mapeado, requiere validación en emulador** | receta §2.3 |
| Invencibilidad / cheats | 💡 Mejor vía player-struct | `docs/uni_ram_analysis.md` |

---

## Apéndice — Regenerar / verificar el build

```python
import struct
data = bytearray(open("ax3201p01.fmem1.dec_original","rb").read())
SITES = [(0x000622,0x204B),(0x0A9184,0x201B),(0x0A9208,0x212B)]   # (offset, 'or' esperado)
for off,exp in SITES:
    assert (data[off]|(data[off+1]<<8))==exp, f"mismatch @0x{off:X}"
    data[off], data[off+1] = 0x09, 0x00      # -> nop
open("ax3201p01.fmem1.dec_bilinear","wb").write(data)
# md5 esperado: af00dbde68b3b1eb2f6dcae4580e3d25
```

*Bilineal: desensamblado directo + tu patch DC ya probado → alta confianza. Menú debug: existe y
está mapeado; su activación permanente necesita una verificación en emulador que no puedo hacer
desde aquí, por eso se entrega como receta y no como parche ciego.*
