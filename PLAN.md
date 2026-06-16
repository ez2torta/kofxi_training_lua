# KOF XI (Atomiswave) — Plan del training Lua para Flycast Dojo

Estado y próximos pasos para retomar en frío. Resume qué funciona, qué falta,
y los caminos para llegar a **posiciones + hitboxes reales** sobre los personajes.

---

## 1. Estado actual (qué YA funciona)

Archivo principal: **`kofxi.lua`** (overlay de training, estilo `cvs2.lua`/`mvsc2.lua`).

Todo esto está **confirmado byte a byte** contra `kofxi.cht` + docs y funciona en vivo:

- **Base de memoria**: `BASE = 0x0C000000` + offset crudo (Flycast enmascara los bits altos).
- **Timer**: `0x131E2C` (+ mirrors `0x27CB78`, `0x27CB7E`). Freeze/unfreeze.
- **Team struct** (100% fiable): P1 `0x27CB54`, P2 `+0x1F8`.
  - super `+0x88` (max `0xE0`), tag/skill `+0x8C` (max `0xE0`).
  - `PlayerExtra[3]` en `+0x150`, stride `0x20`: charID `+0`, isSelected `+1`,
    health `+4` (max `0x70`), visibleHealth `+6`, stun `+8`, guard `+0xA`.
- **Roster** charID→nombre (`0x00` Ash … `0x2F` Kyo EX, `0x28` sin uso).
- **Features**: display vidas/stun/super/tag, restore health, refill super/tag,
  clear stun, toggles inf-health / inf-meter / no-dizzy, forfeit, controles de
  dummy (jump/crouch/toward/away/release/auto-guard).
- **Layout** distribuido para 1080p sin solapes (ventanas en posición fija).

### Limitación conocida
- **Facing es MANUAL** (default P1=derecha, P2=izquierda, con botón flip por dummy).
  El auto-facing está parqueado porque depende del player struct vivo (ver abajo).

---

## 2. El problema de raíz — RESUELTO (2026-06-16)

> **Globales hallados offline** sobre el framecap existente
> (`kof-combo-hitboxes/aw_data/sessions/framecap_20260408_201428`), sin emulador.
> Detalle completo y verificación en
> `kofxi_aw_modding/docs/runtime_globals_aw.md`; script `scripts/find_globals.py`.
>
> | Global | Offset crudo | Contenido |
> |--------|--------------|-----------|
> | **playerTablePtr** | `0x217FD0` | array de **12 punteros SH-4** a entidades ([0..5] chars, [6..11] proy/efectos) |
> | **camera** | `0x27CAA8` | `X`@+0, `Y`@+2 (s16) |
>
> **Regla (sin team.point):** recorrer las 12 entradas; un **luchador activo** es
> el que tiene `animDataPtr(+0x200)` válido (`>>24==0x8C`) **y** `facing(+0x8C) ∈ {0,2}`
> (0=izq, 2=der). Los benched traen `facing 0x3C/0x3E` y `actionCategory(+0x204)=0xFF`.
> Los índices activos cambian con tag/KO → **escanear cada frame, no hardcodear**.
>
> Verificado vs el ndjson ground truth: frame 1000 (cam=896,224) → idx2 X=1444
> face=R (P1≈1437) e idx3 X=1504 face=L (P2=1504). Cadena confirmada.

Las direcciones del **player runtime struct** (posición/facing/acción/hitboxes)
**NO son fijas**: el juego las asigna por partida según los personajes cargados.
Por eso los `0x19xxxx` hardcodeados (de un framecap viejo) leían cero/basura en
otra partida. La solución es seguir la tabla global de arriba.

**La forma correcta** (la usa el visor de PS2, ver
`kofxi_aw_modding/lua/game/pcsx2/kof_xi/game.lua`):

```
playerTablePtr (dirección fija)  ->  struct con p[2][3] punteros SH-4
team.point (índice del char activo)  ->  elige cuál de los 3
deref  ->  player struct vivo:
    position  +0x00 (X,Y world, s16)
    facing    +0x8C (0=izq, 2=der)
    hitboxes  +0x314 (7 slots × 10 bytes)
    hitboxesActive +0x39E (bitmask)
cameraPtr (dirección fija)  ->  camera.position (world->screen)
```

Los **offsets internos del struct ya están confirmados** en AW (coinciden con PS2:
`+0x200/+0x226/+0x2A4/+0x314`). Lo que **falta** son las **direcciones globales AW**:
`playerTablePtr`, `cameraPtr`, y confirmar el offset de `team.point`.

Referencia PS2 (NTSC-U), por si la disposición relativa AW es parecida:
`playerTablePtr 0x008A26E0`, `teamPtrs 0x008A9690/0x008A98D8`, `cameraPtr 0x008A9660`.
(En AW los teams están en `0x27CB54/0x27CD4C`; la cámara en PS2 = team1−0x30.)

---

## 3. Ground truth disponible

`kofxi_aw_modding/rom_samples/kof_xi_hitboxes_20260330_204609.ndjson`
(6007 frames, equipo Ash/Oswald/Shen). Por frame trae:
`camera_x/y`, por jugador `point` + `team[3]` + `world_x/y` + `facing(±1)` +
`super_meter` + `hitboxes_active` + `hitboxes[]` con
`slot, box_id, box_type, rel_x, rel_y, half_w, half_h, full_w, full_h, world_cx, world_cy`.

Hechos verificados con este ndjson:
- **facing == signo(x_rival − x_propio)** (en el cruce del frame ~1600 se invierte solo).
- `box_type` ∈ {attack, vulnerable, counterVuln, projVuln, throw, collision}.
- Proyección de caja (de `game.lua`):
  `centerX = playerX + rel.x*2*facing`, `centerY = playerY − rel.y*2`,
  `w = width*2`, `h = height*2`. Ground Y = `0x2A0` (672).
- frame 0: P1 Ash `world_x=1437 facing=1`, P2 `world_x=1504 facing=-1`, `camera_x=896`.

Esto sirve para **verificar** las direcciones que encontremos (buscar el valor
`1437` en el dump, etc.).

---

## 4. BLOQUEANTE: hace falta un RAM dump de 16MB del AW

Con un dump completo se cazan offline `playerTablePtr` / `cameraPtr` / `team.point`.

### Opción A — usar un dump existente (lo más rápido)
Si hay un **`frame_base.bin` de 16MB** del AW (idealmente el del framecap que
generó el ndjson de hitboxes), usarlo directo. Formato framecap:
`memorysnapshots/sessions/framecap_*/frame_base.bin` (RAM 16MB) + `deltas.bin`
(deltas por página 4KB). Scripts que lo leen: `kofxi_aw_modding/scripts/scan_player_ptrs.py`,
`trace_framecap_anim.py`.

### Opción B — generarlo con el exportador (ya implementado)
Archivo: **`kofxi_ramdump.lua`** (en esta carpeta).
1. Cargarlo en Flycast Dojo **en vez de** `kofxi.lua`.
2. Entrar a un combate en situación conocida (**P1 quieto a la izquierda mirando
   a la derecha, ambos idle**).
3. Botón **"Export full RAM"** → escribe
   `flycast-dojo-training/kofxi_ram.bin` (16MB, ~64 frames / 1-2 s).
4. Anotar la situación exacta capturada (para casar contra el ndjson).

> Si muestra `error: io unavailable`, ese build no permite escribir archivos
> desde Lua. Alternativas: streaming hex a consola, o un savestate de Flycast
> (se puede parsear el bloque de RAM del savestate).

---

## 5. Análisis offline (cuando exista el dump)

Objetivo: encontrar las 3 incógnitas y verificar contra el ndjson.

1. **Localizar los player structs vivos**: buscar structs cuyo `+0xEC` (actionID)
   sea chico, `charID` y `health` coincidan con el team struct, y `+0x00` (X)
   sea ~`world_x` del ndjson (ej. 1437).
2. **Encontrar `playerTablePtr`**: buscar un array de 6 punteros SH-4
   (`0x0C19xxxx`/`0x8C19xxxx`) que apunten a esos structs. Su dirección = el
   puntero global a leer.
3. **Encontrar `cameraPtr`**: struct con X/Y ~ `camera_x/y` (896/224 en frame 0).
   Probable cerca de los teams (en PS2 = team1−0x30 ≈ `0x27CB24`).
4. **Confirmar `team.point`**: el byte del team struct cuyo valor = índice del
   char activo (PS2 = `+0x03`; en AW el front está desplazado, verificar).
5. Verificar offsets de hitbox (`+0x314`, 10B) reproduciendo `world_cx/cy` del
   ndjson con la fórmula de §3.

Herramienta sugerida: un script Python nuevo `find_globals.py` que cargue
`kofxi_ram.bin`, aplique estas búsquedas y vuelque candidatos.

---

## 6. Implementación final (en `kofxi.lua`)

Una vez con las direcciones:

1. Añadir lectura de punteros: `read32` (SH-4) → `(ptr & 0x1FFFFFFF) - 0x0C000000`
   para convertir a offset usable con `BASE`.
2. `getActivePlayer(side)`: leer `playerTablePtr`, indexar `[side][team.point]`,
   deref → base del struct vivo.
3. **Facing automático** = `facingByPos` (signo de la diferencia de X) y/o byte
   `+0x8C`; quitar el flip manual (dejarlo solo como override opcional).
4. **Overlay de hitboxes**: por cada jugador, recorrer `hitboxes[0..6]` filtrando
   con `hitboxesActive`, mapear `box_id`→tipo/color (ver `boxtypes_common.lua` y
   `kof_xi/boxtypes.lua` del repo), proyectar con la cámara y dibujar rectángulos.
   - Revisar qué API de dibujo expone `flycast.ui` (líneas/rects). Si solo hay
     `text`/`button`, evaluar `flycast.overlay`/primitivas disponibles; si no hay
     dibujo de rects, usar caracteres o pedir la API correcta.
5. Proyectiles (opcional): `team.projectiles` `+0xC0` (16 punteros) como en PS2.

---

## 7. Archivos relevantes

- `flycast-dojo-training/kofxi.lua` — overlay de training (actual).
- `flycast-dojo-training/kofxi_ramdump.lua` — exportador de RAM 16MB.
- `flycast-dojo-training/kofxi.cht` — cheats (fuente de direcciones del team).
- `flycast-dojo-training/cvs2.lua` / `mvsc2.lua` — referencia de la API Flycast Dojo.
- `kofxi_aw_modding/lua/game/pcsx2/kof_xi/{game,types,boxtypes,roster}.lua` —
  visor PS2 (plantilla de punteros + hitboxes).
- `kofxi_aw_modding/docs/partial_ps2_analysis/kof_xi_memory_map.md` — layout structs.
- `kofxi_aw_modding/rom_samples/kof_xi_hitboxes_*.ndjson` — ground truth.

---

## 8. TL;DR para retomar

1. ~~Conseguir un RAM dump 16MB~~ ✅ **HECHO** con el framecap existente.
2. ~~Análisis offline (§5)~~ ✅ **HECHO**: `playerTablePtr=0x217FD0`,
   `camera=0x27CAA8`, regla de luchador activo y offsets internos confirmados
   contra el ndjson (ver §2 y `kofxi_aw_modding/docs/runtime_globals_aw.md`).
3. **← AQUÍ:** reescribir `kofxi.lua` para **seguir la tabla** (§6 receta Lua):
   facing/posición reales + **dibujar hitboxes**. Único pendiente menor:
   resolver `team.point` y el dibujo de rects de la API `flycast.ui` (afinable
   en vivo). El RAM dump nuevo (§4) ya **no es bloqueante**; sirve solo para
   re-verificar en otra partida.
