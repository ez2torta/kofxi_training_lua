# KOF XI — Estudio del filtro bilineal y de los menús ocultos (estilo sudden-desu)

> Continuación de [`hallazgos_track04_sram.md`](hallazgos_track04_sram.md).
> Replica la metodología de <https://sudden-desu.net/entry/king-of-fighters-xi-time-release-menu/>
> sobre **tu** copia del ejecutable, y profundiza en el código alrededor del parche de bilineal.
> Fecha: 2026-06-21.

## Mapa de direcciones (memorízalo)

El binario se carga en RAM en **`0x8C010000`**. Por lo tanto:

```
RAM        = offset_en_track04  + 0x8C010000
offset_AW  = offset_en_track04  + 0x100          (header "System X" de 256 bytes)
```

Ejemplo: el parche de bilineal en `track04 0xA9084` ↔ RAM `0x8C0B9084` ↔ `AW 0xA9184`.

---

# PARTE 1 — El filtro bilineal por dentro

## 1.1 Qué toca realmente el parche

Tu `track04_modificado.iso` cambia 3 instrucciones `or` a `nop`. Desensamblando alrededor de
cada una se ve que **NO son tres parches sueltos: son un setter global + dos rutas concretas**
que escriben el mismo *render-attribute word*.

### Sitio 0 — el setter global (`track04 0x522` / RAM `0x8C010522`)

```asm
; helper: "mete los bits R4 en el campo de filtro del contexto de render global"
0x00051A  mov.l @R5,R3          ; R5 = &(*0x8C13D7CC) -> contexto de render global
0x00051C  mov   R3,R2
0x00051E  mov.l @(0x8,R2),R0    ; R0 = ctx->+8   (palabra de atributos)
0x000520  and   R1,R0           ; R0 &= 0x9FFF   -> limpia bits 13 y 14 (0x6000)
0x000522  or    R4,R0           ; R0 |= R4       <== PARCHEADO A NOP
0x000524  rts
```

`*(0x8C13D7CC)` es un puntero en RAM (BSS/heap, fuera del archivo) al **contexto de render
global**. La función limpia los bits 13–14 del campo `+8` y luego les mete `R4` (el modo de
filtro pedido). Al volverlo `nop`, **el campo de filtro queda siempre en 0 → point sampling**,
sin importar lo que pidiera el resto del juego. Justo arriba (`0x510`) hay un gemelo con
máscara `0xF0FF` (otro sub-campo). Este es el parche "maestro".

### Sitios 1 y 2 — la rutina de polígono (`track04 0xA9040`–`0xA9140`)

Esta rutina arma directamente la palabra de atributos en **`struct+0x494`** de un objeto de
render (sin pasar por el setter global). Secuencia real:

```asm
; struct+0x494 = palabra TSP/atributos de 32 bits del objeto
*(+0x494) &= 0xEFFF        ; limpia bit 12 (0x1000)
*(+0x494) &= 0x9FFF        ; limpia bits 13,14 (0x6000)
*(+0x494) |= 0x8000        ; set bit 15
if (flag struct+0x48C) ...
0xA9084  or 0x2000  ->  *(+0x494) |= 0x2000   ; set bit 13   <== PARCHEADO A NOP
         *(+0x4F1) = 2
0xA9108  or 0x4000  ->  *(+0x494) |= 0x4000   ; set bit 14   <== PARCHEADO A NOP
         *(+0x4F3) = 0x0B  ó  0x13   (según byte de modo en struct+0xB5)
```

### Resumen de campos del struct de render

| Offset | Tipo | Rol observado |
|---|---|---|
| `+0x494` | u32 | **Palabra de atributos / TSP word.** Bits 12–15 = filtro de textura. |
| `+0x48C` | u32 | Flags del objeto (se testea `tst #0x08` = bit 3) — gatea la ruta de filtro. |
| `+0x4F1` | u8 | Modo (se pone 2). Sombra/textura-env. |
| `+0x4F2` | u8 | Modo (se pone 3). |
| `+0x4F3` | u8 | Modo (0x0B o 0x13 según `struct+0xB5`). |
| `+0x4F4` | u8 | Modo. |

## 1.2 Interpretación PowerVR2

Los bits 12–15 de esa palabra corresponden al campo de **filtrado de textura** del
*TSP Instruction Word* del PowerVR2/Holly (el modo de muestreo: point / bilinear / trilinear +
super-sample). El código:

- **limpia** los bits del filtro (`and 0xEFFF`, `and 0x9FFF`), y
- **los vuelve a poner** con `or 0x2000`/`or 0x4000` cuando el juego quiere filtrado.

Anular esos `or` deja el campo en su estado "limpio" = **sin filtro = point sampling** (píxeles
nítidos). Esto encaja exactamente con lo que hace tu patch.

> ⚠️ Honestidad técnica: el efecto (bilineal on/off) está confirmado por desensamblado y por tu
> propia prueba. La correspondencia *exacta* bit→nombre del TSP word no la pude confirmar contra
> documentación pública (la referencia de mc.pp.se no detalla el TSP word); para clavarla habría
> que trazar dónde se escribe `struct+0x494` hacia el TA/PVR. Lo seguro es: **bits 12–15 de esa
> palabra = control de filtrado**, y limpiarlos = point sampling.

## 1.3 ¿El patch de 3 sitios cubre TODO el filtrado?

Escaneando el binario completo busqué instrucciones `or` precedidas de una carga de un bit de
filtro (`0x1000/0x2000/0x4000/0x8000`): **~100 sitios candidatos**. La mayoría se agrupan en:

| Rango (track04) | Nº sitios | Probable |
|---|---|---|
| `0x5F000–0x64000` | ~50 | Motor de **sprites 2D** (KOF es 2D): cada capa arma su TSP word con `or 0x4000`. |
| `0xB4000–0xB6000` | ~8 | Otra ruta de render (fondos/efectos). |
| `0xD4000–0xD8000` | ~6 | Otra ruta. |
| `0x522`, `0xA9084`, `0xA9108` | 3 | **Los que toca tu patch.** |

Hay falsos positivos (0x2000/0x4000 también son tamaños de buffer, etc.), pero el patrón sugiere
que **existen más rutas de filtrado que las 3 parcheadas**. Como el setter global (`0x522`) ya
fuerza el campo a 0, es probable que cubra la mayoría; pero si notas que **algunos sprites siguen
suavizados**, los candidatos del cluster `0x5F000–0x64000` son los siguientes a revisar.

Avenida concreta: parchear a `nop` los `or 0x4000` de ese cluster, uno por uno, y comparar en
emulador. (Listado completo de los 100 offsets reproducible con el script del apéndice B.)

---

# PARTE 2 — Menús ocultos (replicando el artículo)

El artículo encuentra un menú **Time Release** fantasma en *Test Menu > Configuration > Game
Settings (página 2)*. Apliqué el mismo método a tu binario y encontré **eso y más**.

## 2.1 Formato de las definiciones de menú

Cada ítem de menú es un registro de **16 bytes**:

```
{ puntero_a_string (4) ; tipo (4) ; color RGBA (4) ; {x:u16, y:u16} (4) }
```

Cada menú termina con un ítem `SAVE&EXIT`, e inmediatamente después hay un **campo contador**
(número de filas del menú). Ese contador es lo que el artículo bumpea de 8 a A.

## 2.2 Menú Game Settings — página 1 y 2

**Página 1** (RAM `0x8C10F480`, track04 `0xFF480`): título `GAME SETTINGS`, luego
`>NEXT PAGE, PLAY TIME, HOW TO PLAY, DIFFICULTY, VERSUS LIMIT, CONTINUE, CONT.SERVICE, BLOOD,
SAVE&EXIT`. Contador tras SAVE&EXIT (`0xFF514`) = `0x0A`.

**Página 2** (track04 `0xFF6D0`): título `GAME SETTINGS`, luego
`>NEXT PAGE, FLASH, VS MODE, BGM VOLUME, SE VOLUME, BUTTON SETTINGS, RETURN TO FACTORY SETTINGS,
SAVE&EXIT` = 8 entradas seleccionables + título.

## 2.3 La dirección del artículo en TU ROM

El artículo dice: cambiar el contador en RAM **`0x8C10F754`** de `0x0008` a `0x000A`.

En tu binario, `0x8C10F754` = **track04 `0xFF754`** (y `AW 0xFF854` — **idéntico en ambos**).
Ahí el valor **ya es `0x00000009`, no `0x0008`**:

```
0xFF750: SAVE&EXIT (fin del menú página 2)
0xFF754: 09 00 00 00   <- contador (RAM 0x8C10F754)  [el artículo esperaba 08]
0xFF758: 08 00 00 00   <- segundo campo (tipo/tamaño de fila, constante 8)
```

**Implicación:** tu revisión del ROM trae el contador ya en `0x09`. Posibilidades:
1. Es una **revisión distinta** a la del artículo (KOF XI Atomiswave tiene varias).
2. El conteo aquí incluye el título (9 filas dibujadas) y la lógica de clamp del cursor está en
   otra parte (el menú se construye en runtime desde plantillas vía un registro maestro, ver 2.5).

Por eso **no te doy un "cambia este byte y listo" a ciegas**: en esta revisión el setup difiere
del artículo. Lo correcto es probar en emulador: pon un watch/cheat en `0x8C10F754` y prueba
`0x0A`/`0x0B` mientras navegas Game Settings pág. 2 para ver si aparece la fila fantasma.

## 2.4 El submenú TIME RELEASE (encontrado)

Existe completo en tu ROM (RAM `0x8C10FA40`, track04 `0xFFA40`):

```
TIME RELEASE SETTINGS
  RELEASE TYPE :   ->  TYPE 0 .. TYPE 5
  RELEASE CHARA    ->  NO CHARA / ADELHIDE / GAI / SILBER / JAZU / HAYATE
  (NO) SAVE&EXIT
```

Esos son **los personajes de time-release de KOF XI**: Adelheid (ADELHIDE), Gai, Silber (=Sho
Hayate?), Jazu, Hayate. "RELEASE TYPE 0–5" elige el calendario de desbloqueo. Este submenú está
listado en el **registro maestro de menús** en `0x8C05BE6C` (track04 `0x4BE6C`), junto a todos
los demás submenús del test mode.

## 2.5 BONUS — Menú DEBUG de desarrollador (¡26 entradas!)

Cerca del time-release hay una **tabla de menú de debug** (track04 `0x4D170`, RAM `0x8C05D170`),
con pares `{dirección_de_flag, label}`. Las 26 entradas incluyen:

```
MUTEKI  (無敵 = invencible)   No Life      Death        Undead
Time Stop   Time Down   Time Over   Wait   Pause   Still   CP   ... (y 15 más)
```

El **flag de MUTEKI vive en RAM `0x8C126DF8`** — exactamente la dirección que el artículo cita
como "debug strings loaded at startup to 0x8C126DF8". Confirmado: es la **base de las variables
de debug**, una por entrada (`0x8C126DF8`, `…E08`, `…E18`, … en pasos de 0x10).

Es decir: el "0x8C126DF8" del artículo es la variable de **invencibilidad del menú de debug**.
Activarla (=1) en RAM debería darte modo invencible. Las demás (No Life, Time Stop, etc.) son los
clásicos toggles de QA.

---

# PARTE 3 — Conexión con la SRAM (desbloqueo de personajes)

El submenú **Time Release** y los personajes (`ADELHIDE/GAI/SILBER/JAZU/HAYATE`) son la cara de
configuración del desbloqueo. El **estado** de qué está desbloqueado se guarda en la SRAM, en el
bloque `SXA_SYSTEM_SETTING` (ver `hallazgos_track04_sram.md` §3). Para aislar el/los byte(s) de
unlock de personajes:

1. En el emulador, entra a Game Settings → (si logras) Time Release → pon RELEASE CHARA = todos /
   RELEASE TYPE alto, guarda.
2. Vuelca la SRAM **antes** y **después**.
3. `XOR` de ambos volcados (script en el doc anterior) → los bytes que cambian dentro de
   `SXA_SYSTEM_SETTING` son los flags de desbloqueo. Recuerda recalcular el checksum del bloque
   (rutina `sx_Sram`, ver doc anterior) si editas a mano.

> Atajo alternativo: el menú de **debug** (`0x8C05D170`) y/o forzar el time-release vía cheat de
> RAM evita tocar la SRAM directamente.

---

# Apéndice A — Direcciones clave

```
Base de carga RAM .......................... 0x8C010000   (track04 file 0)
Setter global de filtro (or) ............... track04 0x000522  RAM 0x8C010522  AW 0x000622   -> nop
Filtro ruta polígono (or 0x2000) ........... track04 0x0A9084  RAM 0x8C0B9084  AW 0x0A9184   -> nop
Filtro ruta polígono (or 0x4000) ........... track04 0x0A9108  RAM 0x8C0B9108  AW 0x0A9208   -> nop
Contexto de render global (puntero) ........ RAM 0x8C13D7CC
Render struct: palabra de filtro ........... +0x494 ; flags +0x48C ; modos +0x4F1..+0x4F4

Game Settings pág. 2 — contador ............ track04 0x0FF754  RAM 0x8C10F754  (vale 0x09 aquí)
Submenú TIME RELEASE (tabla) ............... track04 0x0FFA40  RAM 0x8C10FA40
  strings personajes ....................... track04 0x0FFF18  (NO CHARA/ADELHIDE/GAI/SILBER/JAZU/HAYATE)
Registro maestro de menús .................. track04 0x04BE6C  RAM 0x8C05BE6C
Menú DEBUG (tabla label/flag, 26 entradas) . track04 0x04D170  RAM 0x8C05D170
  flag MUTEKI (invencible) ................. RAM 0x8C126DF8   (base de flags de debug, paso 0x10)
```

# Apéndice B — Reproducir

```python
import struct, re, sys
sys.path.insert(0,'/tmp')                 # sh4dis.py (desensamblador mínimo del análisis)
tr = open("track04_original.iso","rb").read()
BASE = 0x8C010000

# 1) Strings de los menús ocultos
for m in re.finditer(rb'[\x20-\x7e]{3,}', tr[0xFFC00:0x100100]):
    print(hex(0xFFC00+m.start()), m.group().decode())   # TIME RELEASE / MUTEKI / personajes

# 2) Contador del menú del artículo
print("RAM 0x8C10F754 =", struct.unpack('<I', tr[0xFF754:0xFF758])[0])   # 9 en esta ROM

# 3) Tabla del menú DEBUG (pares flag/label)
o = 0x4D170
while True:
    val, lab = struct.unpack('<II', tr[o:o+8])
    if not (0x8c120000 <= val < 0x8c130000): break
    e = tr.find(b'\0', lab-BASE)
    print(f"{val:08X}  {tr[lab-BASE:e].decode('latin1').strip()}")
    o += 8
```

# Apéndice C — Cheats de RAM listos (para emulador, AW)

```
; Invencibilidad (debug MUTEKI)
0x8C126DF8 = 0x00000001

; (experimental) revelar fila fantasma en Game Settings pág.2 — probar valores
0x8C10F754 = 0x0000000A    ; o 0x0B; esta revisión ya trae 0x09, verificar en pantalla
```

---

*Bilineal: desensamblado directo (alta confianza en el comportamiento; etiqueta PVR a confirmar
trazando la escritura al TA). Menús ocultos: tablas y strings hallados en el binario, direcciones
verificadas; el clamp exacto del cursor en esta revisión conviene confirmarlo en emulador.*

Fuentes consultadas para el contexto de hardware:
[sudden-desu — KOF XI Time Release Menu](https://sudden-desu.net/entry/king-of-fighters-xi-time-release-menu/) ·
[Dreamcast Programming — PowerVR (mc.pp.se)](https://mc.pp.se/dc/pvr.html) ·
[Dreamcast Architecture (copetti.org)](https://www.copetti.org/writings/consoles/dreamcast/)
