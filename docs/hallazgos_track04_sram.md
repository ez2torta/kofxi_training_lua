# KOF XI — Relación `track04.iso` ↔ ejecutable Atomiswave, y anatomía de la SRAM

> Análisis hecho el 2026-06-21 sobre los archivos en `/Users/paulosandoval/Documents/kof11`.
> Todo lo de abajo es verificable; al final hay un apéndice con los offsets exactos y el
> código Python para reproducirlo.

---

## TL;DR (lo esencial)

1. **`track04.iso` NO es configuración ni SRAM: es el ejecutable del juego (código SH-4).**
   El "patch del bilinear" lo demuestra: solo cambia **6 bytes** y los convierte en
   instrucciones `nop` (`09 00`). Eso es parchear código máquina, no datos.

2. **El ejecutable de Dreamcast (`track04.iso`) es el ejecutable de Atomiswave
   (`ax3201p01.fmem1.dec_original`) casi idéntico.** Concretamente:

   ```
   ax3201p01.fmem1.dec  =  [header "System X" de 0x100 bytes]  +  el mismo programa que track04.iso
   ```

   El **99.73 %** de `track04.iso` es byte-a-byte igual al ejecutable Atomiswave
   desplazado +0x100. Solo difieren **3193 bytes (0.27 %)** en 26 parches pequeños:
   ahí está todo lo que los porteadores ("los chinos") tocaron para que corra en Dreamcast.

3. **El "bilinear" NO está en la SRAM.** Es un *flag hardcodeado en el código* que arma la
   palabra TSP del PowerVR. Por eso no aparece en el menú de configuración y hubo que parchear
   instrucciones. (Detalle exacto en la sección 2.)

4. **La SRAM (los `.nvmem`) solo guarda contabilidad de operador y records**, no opciones
   gráficas. Sus bloques están etiquetados `SXA_*` ("**S**ystem **X** **A**tomiswave") y cada
   uno lleva un **checksum de 4 bytes** + está **duplicado** (copia principal + respaldo).

5. **El ejecutable SÍ "tiene cosas de la SRAM"**, pero no los *valores*: tiene el **esquema**
   (la tabla de nombres de bloque) y **todo el subsistema que la gestiona** (módulos
   `sx_Sram`, `sx_BackupSrv`, `sx_Bookkeeping`/`SXABOOK`, `sx_SystemBackup`). La rutina de
   checksum vive ahí.

6. **Para depurar/editar la SRAM falta una sola cosa: el algoritmo del checksum.** No es
   CRC32 ni una suma simple → es la rutina propia de `sx_Sram` (en el ejecutable, ver
   sección 5). Sin recalcular ese checksum, el juego detecta el bloque corrupto y lo borra
   al arrancar.

---

## 0. Inventario de archivos

| Archivo | Tamaño | Qué es |
|---|---|---|
| `ax3201p01.fmem1.dec_original` | 8,388,608 (0x800000) | Flash region 1 del cartucho **Atomiswave** de KOF XI, **descifrada**. Empieza con header arcade "System X". |
| `track04_original.iso` | 1,191,936 (0x123000) | **Ejecutable del port a Dreamcast** (a pesar de la extensión `.iso`, es un binario crudo SH-4, no un ISO9660). |
| `track04_modificado.iso` | 1,191,936 | Igual que el anterior **+ patch de bilinear** (6 bytes). |
| `King of Fighters XI GDI Track4 ... .zip` | 177 MB | El track de datos "grande" del GDI (recursos/gráficos). No es lo mismo que el `track04.iso` chico de arriba. |
| `rom_samples/saves/*.nvmem` | 131,072 (0x20000) c/u | Volcados de **SRAM/backup-RAM** (formato NVMEM de Flycast). 128 KB. |

> Nota sobre nombres: hay dos "track 4" distintos. El `.iso` de 1.19 MB es el **programa**
> (lo que aquí se analiza). El `.zip` de 177 MB es el **track de datos** con los recursos.

---

## 1. `track04.iso` vs el ejecutable Atomiswave

### 1.1 El desplazamiento constante de +0x100

Muestreando 568 fragmentos de 48 bytes a lo largo de `track04.iso` y buscándolos en el
ejecutable Atomiswave, **526 (93 %)** aparecen con un offset constante de **+0x100 (256 bytes)**:

```
track04_offset + 0x100  ==  AW_offset
```

Los primeros 0x100 bytes del ejecutable Atomiswave (que `track04.iso` NO tiene) son el
**header de cartucho de Sammy "System X"**:

```
0x000000: "SYSTEM_X_APP    SNK-PLAYMORE    ..."
```

(Atomiswave internamente se llama *Sammy System X*.) Es decir, **el port a Dreamcast es el
binario del Atomiswave con el header de arcade de 256 bytes quitado.**

### 1.2 Diff exacto alineado (delta 0x100)

Comparando `track04[i]` contra `AW[i+0x100]` byte a byte:

- **1,188,743 bytes idénticos = 99.73 %**
- **3,193 bytes distintos = 0.27 %**, agrupados en **26 regiones**.

Esas 26 regiones son **todo lo que cambió el porteo**. Las principales:

| track04 offset | Long. | Interpretación |
|---|---|---|
| `0x122820 – 0x123000` | 2016 | **Truncado.** track04 termina en datos a 0x122820 y rellena con ceros hasta fin de sector. En el AW siguen datos (matrices/tablas PVR). → track04 = solo la porción de *programa*; el resto del flash de 8 MB (gráficos/sonido) va en otros tracks del GDI. |
| `0x02E412 – 0x02E678` | 614 | **Capa de E/S reescrita.** Donde el AW tiene muchos epílogos `rts; nop` (rutinas chicas de hardware arcade: JVS, watchdog Sammy), el DC los reemplaza por código más compacto (Maple bus / GD-ROM). |
| `0x02F21A – 0x02F37C` | 354 | Otra rutina de E/S/inicialización reescrita (mismo patrón). |
| `0x011288 – 0x0112DB` | 83 | **Tabla de máscaras de botones** cambiada (`FF FE FF FF` ↔ `FF FF FE FF`): remapeo de input JVS → mandos Maple. |
| `0x02F12A – 0x02F150` | 38 | Parche de E/S. |
| `0x0C58B6` y `0x0C5926` | 28 c/u | **Bloque del AW anulado a `nop`** en el DC: se eliminó un chequeo propio del arcade (probablemente región/JVS). |
| `0x0EBBCD`, `0x0D914A`, `0x0EBC5E…` | 3–19 | Direcciones/targets de salto reajustados; constantes de hardware. |
| ~12 parches de 2–4 bytes | 2–4 | Direcciones de registros de hardware (Holly/AICA vs CLX2/AW) cambiadas puntualmente. |

**Conclusión de la sección:** sí, "hay partes de `track04.iso` en el ejecutable del juego" —
de hecho **prácticamente todo** `track04.iso` está dentro del ejecutable Atomiswave. El "patrón
que se va copiando" es el programa entero; lo único que cambia son ~26 parches quirúrgicos de
adaptación a Dreamcast.

---

## 2. El "patch del bilinear" (qué hace realmente)

El diff entre `track04_original.iso` y `track04_modificado.iso` son **exactamente 6 bytes
(3 instrucciones de 16 bits)**, todas convertidas a `nop` (`09 00` en SH-4 little-endian):

| Offset en track04 | Offset en AW (+0x100) | Instrucción original | Pasa a |
|---|---|---|---|
| `0x000522` | `0x000622` | `or R4, R0` (0x204B) | `nop` |
| `0x0A9084` | `0x0A9184` | `or R1, R0` (0x201B) | `nop` |
| `0x0A9108` | `0x0A9208` | `or R2, R1` (0x212B) | `nop` |

Los dos sitios en `0x0A90xx` están en una rutina de armado de polígonos. Justo antes de cada
`or` se cargan constantes de una *literal pool* y se combinan:

```
site 1 (0xA9084):  R0 = 0x0494 ; R1 = 0x2000 ; or R1,R0  →  R0 = 0x2494
site 2 (0xA9108):  R1 = ...    ; R2 = 0x4000 ; or R2,R1  →  setea bit 0x4000
```

`0x2000` (bit 13) y `0x4000` (bit 14) son el campo **Filter Mode** de la **TSP Instruction
Word** del PowerVR2 / Holly (CLX2). Ese campo controla el filtrado de texturas:

```
Filter Mode (bits 13:12 de la TSP word):
  0 = Point sampling (sin filtro, píxeles nítidos)
  1 = Bilinear
  2/3 = Trilinear A/B
```

Al `nop`-ear los `or`, esos bits **ya no se setean** → `Filter Mode = 0` = **point sampling**.
Es decir, **el patch desactiva el filtrado bilineal** (deja la imagen pixelada/nítida). El
tercer sitio (`0x522`, en el boot temprano) es un flag global relacionado de la misma rutina.

> Por eso "no está en la configuración": el bilineal no es una opción guardada en SRAM ni un
> ítem de menú; es un valor **cableado en el código** que arma la palabra TSP. La única forma
> de cambiarlo es parchear el ejecutable, que es justo lo que hace tu `track04_modificado.iso`.

**Corolario útil:** como esos 3 sitios existen *idénticos* en el ejecutable Atomiswave
(`0x000622`, `0x0A9184`, `0x0A9208`), **el mismo patch se puede aplicar a la versión Atomiswave**
cambiando esas 3 palabras a `09 00`.

---

## 3. ¿Qué hay realmente en la SRAM? (`.nvmem`)

Los 4 archivos `.nvmem` son volcados de la **backup-RAM** de 128 KB, pero solo ~0.5 % tiene
datos. Todo vive en dos zonas: **0x0000–0x1000** (operador/sistema) y **0x2000–0x2300** (records).

### 3.1 Bloques etiquetados `SXA_*`

| Offset (save) | Etiqueta | Contenido |
|---|---|---|
| `0x00F0` | `SXA_TOTAL_TIME` | Tiempo total encendido / jugado (contadores). |
| `0x0138` | `SXA_CREDIT_CONF` | Configuración de créditos (coin→credit). |
| `0x01D8` | `SXA_COIN_NUM` | Contadores de monedas. |
| `0x024C` | `SXA_SYSTEM_SETTING` | **Ajustes de sistema** (región, dificultad, free play, etc. — lo que cambia el TEST MENU). |
| `0x030A` | `SXA_CREDIT` | Créditos actuales. |
| `0x03B0` | `SXA_MVSPTIME` | Tiempos de play (estadística). |
| `0x0518` | `SXA_MVSPINFO` | Info de play (estadística). |
| `0x2000–0x2300` | (`SNK` / `KOF`) | **Tabla de records / ranking** (ver 3.3). |

### 3.2 Formato de cada bloque (importante para editarlo)

Cada registro tiene esta forma y está **guardado dos veces** (principal + respaldo):

```
[ payload (N bytes) ][ checksum (4 bytes) ][ nombre "SXA_xxx\0" relleno con NUL ]
```

Ejemplo real — `SXA_TOTAL_TIME` ocupa 0x0E0–0x120 en **dos copias de 32 bytes**:

```
0x0E0:  E2 3C E0 16 00 00 00 00 2A 48 E0 15  85 DF B0 E2   ← payload(12) + checksum(4)
0x0F0:  "SXA_TOTAL_TIME\0\0"                                ← nombre (16)
0x100:  E1 3C E0 16 00 00 00 00 29 48 E0 15  12 7E B1 73   ← copia 2 (contadores +1)
0x110:  "SXA_TOTAL_TIME\0\0"
```

Las dos copias pueden tener valores ligeramente distintos (son generaciones del contador) y
**cada una su propio checksum** → no es un mirror tonto, es redundancia con verificación.

### 3.3 Zona de records (0x2000+)

Es la **tabla de high-scores / ranking** con iniciales por defecto `SNK` y `KOF` y puntajes en
descendente (3 bytes LE):

```
0x20F2:  "SNK"  ... 40 42 0F  → 0x0F4240 = 1,000,000
0x2102:  "SNK"  ... A0 BB 0D  → 0x0DBBA0 =   900,000
0x2112:  "SNK"  ... 00 35 0C  → 0x0C3500 =   800,000
0x220A:  "KOF"  ... (ranking de supervivencia, ranks 0x1E,0x1F,0x20...)
```

---

## 4. ¿"Está todo en la SRAM"? — reparto ejecutable vs SRAM

No. El reparto es claro:

| Cosa | ¿Dónde vive? |
|---|---|
| Bilineal / filtrado de texturas | **Ejecutable** (flag cableado en la TSP word). NO en SRAM. |
| Lógica del juego, gráficos, sonido | **Ejecutable** + tracks de datos del GDI. |
| **Esquema** de la SRAM (nombres `SXA_*`) | **Ejecutable**, tabla en AW `0x122860` / track04 `0x122760`. |
| **Valores por defecto** y rutina de init/checksum de la SRAM | **Ejecutable** (módulo `sx_Sram`). |
| Región, dificultad, free-play, coin config | **SRAM** (`SXA_SYSTEM_SETTING`, `SXA_CREDIT_CONF`). |
| Créditos, monedas, tiempos, bookkeeping | **SRAM** (`SXA_CREDIT`, `SXA_COIN_NUM`, `SXA_TOTAL_TIME`, `SXA_MVSP*`). |
| High-scores / ranking | **SRAM** (zona 0x2000, `SNK`/`KOF`). |

Es decir: la SRAM guarda **lo que el operador puede cambiar desde el TEST MENU + la
contabilidad + los records**. Todo lo "fijo" del juego (incluido el bilineal) está en el código.

### 4.1 El ejecutable lleva TODO el subsistema "System X"

En `AW 0x104400–0x105F00` (= `track04 0x104300–0x105E00`) está el menú de servicio/test
completo del Atomiswave, con sus módulos identificados por strings de versión:

```
sx_SystemMenu   sx_TestMenu     sx_CoinSetting   sx_ConfigMenu    sx_ClearMenu
sx_LongBook(SXABOOK)  sx_BackupSrv  sx_Sram  sx_SystemBackup  sx_Bookkeeping
sx_ClockSetting  sx_ColorTest  sx_CrossHatch  sx_SoundTest  sx_MemoryTest  sx_Gun  sx_Output
```

Strings reveladores: `BACKUP CLEAR`, `HIGH SCORE CLEAR`, `CREDIT CLEAR`, `BOOKKEEPING CLEAR`,
`ALL SRAM DATA WILL BE CLEARED AND SYSTEM REBOOT`, `DAILY/MONTHLY PLAY DATA`, `TOTAL TIME`, etc.
→ es literalmente el gestor de la SRAM que estamos viendo en los `.nvmem`.

---

## 5. Depurar la SRAM: qué falta exactamente

La SRAM ya está **mapeada** (bloques, nombres, formato, doble copia, zona de records). Lo único
que falta para poder **editarla y que el juego la acepte** es:

### 5.1 El algoritmo del checksum (la pieza que falta)

Cada bloque tiene 4 bytes de checksum. **No es CRC32 ni suma simple** (se probó y no coincide).
Es una rutina propia que vive en el módulo **`sx_Sram`** del ejecutable:

```
sx_Sram      Ver 0.90  Build:Jun 10 2005   →  AW 0x105101  /  track04 0x105001
sx_BackupSrv Ver 0.90  Build:Mar 04 2004   →  AW 0x1050C9  /  track04 0x104FC9
```

El siguiente paso para "depurar la SRAM" es **desensamblar esa rutina** (alrededor de esos
offsets) y reimplementar el checksum. Sin eso, cualquier byte que edites a mano hará que el
juego marque el bloque como corrupto y lo **borre/regenere al arrancar** (de ahí los menús
`BACKUP CLEAR` / `ALL SRAM DATA WILL BE CLEARED`).

> Tienes `dcdis-0.4a` en el repo (desensamblador SH-4). Apuntándolo a `track04.iso` en
> `0x105001` deberías ver la función del checksum.

### 5.2 Cuidado con la doble copia

Al editar un valor hay que actualizar **las dos copias** del bloque (y sus dos checksums), o el
juego puede preferir la copia "buena" y revertir tu cambio.

### 5.3 Lo que YA tienes para depurar

- El **mapa de bloques** (sección 3).
- Los **nombres de bloque** en el ejecutable (tabla en `0x122760`) para confirmar el orden.
- El **código del gestor** (`sx_Sram`, `sx_BackupSrv`, `sx_Bookkeeping`) localizado.
- Saves de referencia para diffear (sección 6).

---

## 6. Saves `locked` vs `unlocked`

Diff entre las parejas (`save_locked` ↔ `save_unlocked` y `…default.spanish` ↔ `…unlocked.spanish`):
difieren ~160–215 bytes, casi todos en **contadores, fechas y checksums**, no en grandes
estructuras. Ejemplos:

- **Fechas** (año LE): `EA 07 03 15` = 2026-03-21 vs `E3 07 0A 09` = 2019-10-09 → distintas sesiones.
- **Flags 01→02 / 02→04** en `0x2C0` y bloque `SXA_CREDIT` (`0x308`): contadores/estado de créditos.
- **Checksums** (los 4 bytes antes de cada nombre) cambian junto con su payload, como es de esperar.

⚠️ Observación honesta: por el contenido, **estos pares parecen volcados de sesiones distintas
de operador (créditos/fechas/contadores)**, no necesariamente "personajes desbloqueados vs
bloqueados". Si el objetivo era capturar el bit de *unlock* de personajes secretos, conviene
hacer un volcado **antes** y **después** de desbloquear en el emulador, dejando todo lo demás
igual, y diffear esos dos — así el `XOR` aísla exactamente el/los byte(s) del unlock.

---

## Apéndice A — Offsets clave (referencia rápida)

```
Header System X (solo en AW):           AW 0x000000 .. 0x0000FF
Relación de offsets:                    AW = track04 + 0x100  (en el 99.73% del archivo)
Sitios del patch bilinear (track04):    0x000522, 0x0A9084, 0x0A9108  →  poner 09 00
Sitios del patch bilinear (AW):         0x000622, 0x0A9184, 0x0A9208  →  poner 09 00
Tabla de nombres de bloque SRAM:        AW 0x122860 / track04 0x122760
Gestor de SRAM (sx_Sram):               AW 0x105101 / track04 0x105001
Gestor de backup (sx_BackupSrv):        AW 0x1050C9 / track04 0x104FC9
Menú test/servicio:                     AW 0x104400 .. 0x105F00
SRAM: zona sistema/operador:            0x0000 .. 0x1000
SRAM: zona records (SNK/KOF):           0x2000 .. 0x2300
```

## Apéndice B — Cómo reproducir

```python
aw = open("ax3201p01.fmem1.dec_original","rb").read()
tr = open("track04_original.iso","rb").read()

# 1) Confirmar relación +0x100 y % idéntico
same = sum(1 for i in range(len(tr)) if i+0x100 < len(aw) and tr[i]==aw[i+0x100])
print(f"{same/len(tr)*100:.2f}% idéntico (AW = track04 + 0x100)")   # ~99.73%

# 2) Patch bilinear (poner nop)
for off in (0x000522, 0x0A9084, 0x0A9108):
    print(hex(off), tr[off:off+2].hex())   # 4B 20 / 1B 20 / 2B 21  -> 09 00

# 3) Tags de la SRAM
import re
sav = open("rom_samples/saves/save_unlocked.nvmem","rb").read()
for m in re.finditer(rb'SXA_[A-Z_]+', sav):
    print(hex(m.start()), m.group().decode())
```

---

*Documento generado a partir del análisis binario de los archivos en `Documents/kof11`.
Las afirmaciones sobre el checksum de la SRAM y el campo Filter Mode de la TSP word son las
conclusiones que conviene validar desensamblando `sx_Sram` (0x105001) y la rutina de render
(0x0A9000) respectivamente — todo lo demás es diff/coincidencia binaria directa.*
