# Acelerador CORDIC para la ALU

Proyecto 1 — Arquitectura de Computadoras (CS3051), ciclo 2026-II.

Implementación de un acelerador CORDIC que calcula seno y coseno, en dos versiones:
1. **Hardware en Verilog** (Problema 1): Módulo iterativo multiciclo con FSM explícita de 5 estados e integrado en una ALU de 32 bits con protocolo de sincronización (`start`, `busy`, `done`).
2. **Software en Assembly RISC-V** (Problema 2): Subrutina RV32I pura con instrucciones base nativas (sin pseudoinstrucciones operativas, sin punto flotante ni extensión M).

Ambas versiones comparten idéntico formato de punto fijo (Q2.30 con signo) y el mismo algoritmo iterativo, produciendo **resultados idénticos bit a bit**.

---

## Archivos del Repositorio

| Archivo | Contenido |
|---|---|
| `cordic.v` | Acelerador CORDIC iterativo con FSM de 5 estados (`ROT_POS` / `ROT_NEG`). |
| `alu32.v` | ALU de 32 bits que integra el CORDIC como operación multiciclo (`OP = 4'b1001`). |
| `tb_cordic.v` | Testbench del acelerador: valida 5 ángulos requeridos + negativos, midiendo error absoluto y relativo. |
| `tb_alu32.v` | Testbench de la ALU: valida las 10 operaciones, banderas aritméticas y protocolo multiciclo. |
| `cordic.s` | Subrutina y programa de prueba en RISC-V RV32I puro, compatible con RARS y Venus. |
| `Makefile` | Automatización de compilación y simulación con Icarus Verilog y vvp. |
| `design.v`, `testbench.v` | ALU inicial de 4 bits provista como punto de partida. |

---

## Cómo Ejecutar las Simulaciones

### 1. Simulación Hardware (Verilog) con Icarus Verilog

```bash
make cordic   # Valida el acelerador CORDIC (tb_cordic.v)
make alu      # Valida la ALU de 32 bits y operaciones (tb_alu32.v)
make all      # Ejecuta ambas pruebas
make clean    # Limpia archivos ejecutables y volcados .vcd
```

Los bancos de prueba generan archivos de ondas (`cordic.vcd` y `alu32.vcd`) visualizables mediante **GTKWave**.

### 2. Simulación Software (Assembly RISC-V)

El archivo `cordic.s` está optimizado para simuladores RISC-V como **RARS** o **Venus**:
1. Abrir `cordic.s` en RARS/Venus.
2. Ensamblar y ejecutar (`Run` o `F5`).
3. Inspeccionar las posiciones de memoria en las etiquetas `.data`:
   * `cos_result`: 5 palabras de 32 bits con los cosenos calculados.
   * `sin_result`: 5 palabras de 32 bits con los senos calculados.
   * `error_count`: contador de comprobaciones fuera de tolerancia (debe ser `0`).

---

## Representación de los Datos: Punto Fijo Q2.30

Se utiliza **Q2.30 con signo (Complemento a dos)** de forma idéntica en hardware y software:

| Parámetro | Valor |
|---|---|
| Bits totales | 32 bits |
| Bits parte entera | 2 bits (1 de signo + 1 de magnitud) |
| Bits parte fraccionaria | 30 bits |
| Rango representable | $[-2.0, +1.999999999]$ |
| Resolución / LSB | $2^{-30} \approx 9.3132 \times 10^{-10}$ |

* **Fórmula de conversión:** $\text{valor\_fijo} = \text{round}(\text{valor\_real} \times 2^{30})$.
* **Justificación técnica:**
  * Las salidas trigonométricas están acotadas a $[-1.0, +1.0]$.
  * Los ángulos de entrada exigidos ($0^\circ$ a $90^\circ$) llegan hasta $\pi/2 \approx 1.5708$ rad, que cabe con holgura en $[-2, 2)$.
  * Se asigna el máximo número posible de bits a la parte fraccionaria (30 bits), minimizando los errores de cuantización y redondeo.

---

## Compensación de Ganancia ($K_{16}$) y Tabla de Ángulos

### 1. Ganancia CORDIC
En cada iteración, la rotación elemental agranda la magnitud del vector por un factor $\sqrt{1 + 2^{-2i}}$. Al cabo de 16 iteraciones, la ganancia acumulada es:
$$K_{16} = \prod_{i=0}^{15} \sqrt{1 + 2^{-2i}} \approx 1.646760258$$

Para eliminar la necesidad de un divisor o multiplicador de hardware al final, el vector se **pre-escala al inicio** en el estado `S_INIT`:
$$x_0 = \frac{1}{K_{16}} \approx 0.607252935 \implies x_0 \text{ en Q2.30} = \text{round}(0.607252935 \times 2^{30}) = \mathbf{652032874} \quad (\text{32'd652032874})$$
$$y_0 = 0, \quad z_0 = \theta$$
Al estirarse a lo largo de las 16 iteraciones, el vector termina con magnitud unitaria exacta ($x_{16} \approx \cos\theta, y_{16} \approx \sin\theta$).

### 2. Tabla de Ángulos Elementales ($\alpha_i = \arctan(2^{-i})$)
La tabla almacena los 16 ángulos en formato Q2.30 en radianes para permitir sumas y restas directas con el registro $z$:
* $\alpha_0 = \arctan(1) = 0.785398163\text{ rad} \implies \mathbf{843314857}$
* $\alpha_1 = \arctan(0.5) = 0.463647609\text{ rad} \implies \mathbf{497837829}$
* $\alpha_2 = \arctan(0.25) = 0.244978663\text{ rad} \implies \mathbf{263043837}$
* ...
* $\alpha_{15} = \arctan(2^{-15}) = 0.000030518\text{ rad} \implies \mathbf{32768}$

---

## Máquina de Estados Finitos (FSM de 5 Estados)

Para explicitar el sentido de rotación en el hardware y responder cabalmente a la **Ficha de Evaluación**, el módulo `cordic.v` utiliza una FSM de 5 estados:

```
        ┌────────┐  start   ┌────────┐   angle >= 0    ┌───────────┐
        │ S_IDLE ├─────────►│ S_INIT ├────────────────►│ S_ROT_POS │◄────┐
        └────────┘          └────────┘                 └─────┬─────┘     │ z_next >= 0
             ▲                   ▲       angle < 0           │           │
             │                   │      ┌────────────────────┘           │
             │                   │      │                                │
             │                   │      ▼ z_next < 0                     │
             │                   │ ┌───────────┐                         │
             │                   │ │ S_ROT_NEG ├─────────────────────────┘
             │                   │ └─────┬─────┘
             │                   │       │ iter == 15 (desde POS o NEG)
             │                   │       ▼
             │                   │  ┌────────┐
             │                   └──┤ S_DONE │
             └────── reset ─────────┴───┬────┘
                                        │ start == 0
                                        └──► (mantiene cos_out, sin_out, done=1)
```

### Comportamiento detallado de los estados:
1. **`S_IDLE` (3'd0):** Reposo. Las salidas mantienen el último valor calculado. `done = 0`.
2. **`S_INIT` (3'd1):** Carga inicial ($x \leftarrow \text{INV\_K}$, $y \leftarrow 0$, $z \leftarrow \text{angle}$, $\text{iter} \leftarrow 0$). Transiciona a `S_ROT_POS` si $\text{angle} \ge 0$, o a `S_ROT_NEG` si $\text{angle} < 0$.
3. **`S_ROT_POS` (3'd2) — Rotación Horaria ($d_i = +1$):**
   * Se ejecuta cuando el residuo angular $z \ge 0$.
   * Operaciones: $x \leftarrow x - (y \ggg i)$, $y \leftarrow y + (x \ggg i)$, $z \leftarrow z - \alpha_i$, $\text{iter} \leftarrow \text{iter} + 1$.
   * Transición: Si $\text{iter} == 15 \to$ `S_DONE`. Si no, pasa a `S_ROT_POS` o `S_ROT_NEG` según el signo de $z_{\text{next}}$.
4. **`S_ROT_NEG` (3'd3) — Rotación Antihoraria ($d_i = -1$):**
   * Se ejecuta cuando el residuo angular $z < 0$.
   * Operaciones: $x \leftarrow x + (y \ggg i)$, $y \leftarrow y - (x \ggg i)$, $z \leftarrow z + \alpha_i$, $\text{iter} \leftarrow \text{iter} + 1$.
   * Transición: Si $\text{iter} == 15 \to$ `S_DONE`. Si no, pasa a `S_ROT_POS` o `S_ROT_NEG` según el signo de $z_{\text{next}}$.
5. **`S_DONE` (3'd4):** Publicación de resultados finales (`cos_out = x`, `sin_out = y`, `done = 1`). Permanece activo reteniendo los datos hasta que llegue un nuevo pulso de `start`.

**Latencia total garantizada:** Exactamente **18 ciclos de reloj** (1 ciclo de setup en INIT + 16 ciclos de rotación + 1 ciclo al entrar a DONE).

---

## Interfaz de Módulos

### `cordic.v`
Cumple estrictamente la interfaz de la Sección 4.8 del enunciado:
* **Entradas:** `clk`, `reset`, `start`, `angle` (32 bits con signo, Q2.30).
* **Salidas:** `cos_out` (32 bits con signo), `sin_out` (32 bits con signo), `done` (1 bit).

### `alu32.v`
Integra el CORDIC junto a 9 operaciones combinacionales clásicas:

| OP | Operación | Tipo | Descripción |
|---|---|---|---|
| `0000` | ADD | Combinacional | $A + B$, banderas Z, N, C, V |
| `0001` | SUB | Combinacional | $A - B$, banderas Z, N, C (sin préstamo), V |
| `0010` | AND | Combinacional | $A \ \& \ B$ |
| `0011` | OR  | Combinacional | $A \ \| \ B$ |
| `0100` | XOR | Combinacional | $A \ \text{^} \ B$ |
| `0101` | SLL | Combinacional | Desplazamiento lógico a la izquierda |
| `0110` | SRL | Combinacional | Desplazamiento lógico a la derecha |
| `0111` | SRA | Combinacional | Desplazamiento aritmético con signo |
| `1000` | SLT | Combinacional | Comparación menor que con signo ($A < B \to 1 : 0$) |
| `1001` | **CORDIC** | **Multiciclo (18 ciclos)** | Coseno en `Result`, Seno en `Result_hi` |

---

## Implementación en RISC-V RV32I Puro (`cordic.s`)

El código Assembly cumple con el estándar estricto de no utilizar instrucciones de punto flotante ni extensiones no contempladas:

### 1. Eliminación de pseudoinstrucciones operativas
Todas las operaciones intermedias se sustituyeron por instrucciones nativas del conjunto base RV32I:
* `mv rd, rs` $\to$ `addi rd, rs, 0`
* `j label` $\to$ `jal zero, label`
* `ret` $\to$ `jalr zero, ra, 0`
* `bltz rs, label` $\to$ `blt rs, zero, label`
* `bgez rs, label` $\to$ `bge rs, zero, label`
* `li rd, imm` $\to$ `addi rd, zero, imm`
* Carga de la constante de 32 bits ($652032874$): Descompuesta en `lui t0, 159188` seguido de `addi t0, t0, -1174`.

### 2. Uso de `la`
Se preserva la directiva `la` (Load Address) para la carga de punteros a tablas y arreglos de datos (`atan_table`, `angles`, etc.), garantizando la compatibilidad portable entre RARS (base `.data` en `0x10010000`) y Venus (base `.data` en `0x10000000`).

---

## Resultados y Validación de Precisión

Tanto el testbench de Verilog (`tb_cordic.v`) como el programa en RISC-V (`cordic.s`) evalúan los 5 casos de prueba obligatorios, reportando valores esperados, obtenidos, error absoluto y error relativo:

| Ángulo | $\cos(\theta)$ esperado | $\cos(\theta)$ obtenido | Error Absoluto $\cos$ | $\sin(\theta)$ esperado | $\sin(\theta)$ obtenido | Error Absoluto $\sin$ |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **0°** | 1.000000000 | 0.999999993 | $6.52 \times 10^{-9}$ | 0.000000000 | -0.000017593 | $1.76 \times 10^{-5}$ |
| **30°** | 0.866025404 | 0.866018117 | $7.29 \times 10^{-6}$ | 0.500000000 | 0.500012618 | $1.26 \times 10^{-5}$ |
| **45°** | 0.707106781 | 0.707095801 | $1.10 \times 10^{-5}$ | 0.707106781 | 0.707117761 | $1.10 \times 10^{-5}$ |
| **60°** | 0.500000000 | 0.500012618 | $1.26 \times 10^{-5}$ | 0.866025404 | 0.866018117 | $7.29 \times 10^{-6}$ |
| **90°** | 0.000000000 | -0.000017593 | $1.76 \times 10^{-5}$ | 1.000000000 | 0.999999993 | $6.52 \times 10^{-9}$ |

* **Error máximo observado:** $1.76 \times 10^{-5}$, perfectamente acotado por el límite teórico de 16 iteraciones ($\arctan(2^{-15}) \approx 3.05 \times 10^{-5}$ rad).
* **Tolerancia en testbenches:** $1.0 \times 10^{-4}$ ($131072$ en Q2.30), cumplida holgadamente en el 100% de las pruebas con **0 fallos**.
