# Acelerador CORDIC para la ALU

Proyecto 1 — Arquitectura de Computadoras (CS3051), ciclo 2026-II.

Implementación de un acelerador CORDIC que calcula seno y coseno, en dos
versiones: hardware en Verilog (Problema 1) y software en Assembly RISC-V
(Problema 2). Ambas usan el mismo formato de punto fijo y el mismo algoritmo,
y producen resultados idénticos bit a bit.

## Archivos

| Archivo | Contenido |
|---|---|
| `cordic.v` | Acelerador CORDIC iterativo con FSM. Es el núcleo del proyecto. |
| `alu32.v` | ALU de 32 bits que integra el CORDIC como operación multiciclo. |
| `tb_cordic.v` | Validación del acelerador: 5 ángulos, error absoluto y relativo. |
| `tb_alu32.v` | Validación de la ALU: operaciones, flags y protocolo multiciclo. |
| `cordic.s` | Versión software del algoritmo en RV32I, con programa principal. |
| `Makefile` | Atajos para compilar y correr las simulaciones. |
| `design.v`, `testbench.v` | ALU de 4 bits inicial, previa a la extensión a 32 bits. |

## Cómo ejecutar

Simulación hardware, con [Icarus Verilog](http://iverilog.icarus.com/):

```
make cordic   # validación del acelerador CORDIC
make alu      # validación de la ALU de 32 bits
make all      # ambas
make clean
```

Ambos testbenches generan un `.vcd` que se puede abrir con GTKWave.

La versión software (`cordic.s`) está escrita para ensambladores tipo RARS o
Venus: se carga el archivo, se ejecuta y se inspecciona la memoria en las
etiquetas `cos_result`, `sin_result` y `error_count`.

## Representación de los datos

Se usa **Q2.30 con signo** (complemento a dos), idéntica en hardware y software.

| Parámetro | Valor |
|---|---|
| Bits totales | 32 |
| Parte entera | 2 (1 de signo + 1 de magnitud) |
| Parte fraccionaria | 30 |
| Rango representable | `[-2.0, +1.999999999]` |
| Precisión (LSB) | `2^-30` = 9.3132e-10 |

La conversión es `valor_fijo = round(valor_real * 2^30)`.

Se eligió un solo bit de magnitud entera porque `|x|` e `|y|` nunca superan 1.0
—el vector arranca normalizado con `1/K₁₆`— y el ángulo de entrada llega como
máximo a `π/2` = 1.5708 rad. Todo cabe en `[-2, 2)` y queda el máximo número de
bits para la parte fraccionaria, que es donde vive la precisión del resultado.

## Precisión obtenida

Con **N = 16 iteraciones** el ángulo residual queda acotado por
`arctan(2^-15)` = 3.0518e-05 rad, y ese es el error que domina. El LSB del
formato (9.3e-10) queda cuatro órdenes de magnitud por debajo, así que **el
límite lo pone el número de iteraciones, no la representación**.

El margen de error usado en los testbenches es `1.0e-04`, con un factor de
holgura de unas 5 veces sobre el peor caso teórico.

Resultados medidos (idénticos en Verilog y en RISC-V):

| Ángulo | cos esperado | cos obtenido | err. abs. | sin esperado | sin obtenido | err. abs. |
|---|---|---|---|---|---|---|
| 0° | 1.000000000 | 0.999999998 | 1.86e-09 | 0.000000000 | -0.000017593 | 1.76e-05 |
| 30° | 0.866025404 | 0.866018117 | 7.29e-06 | 0.500000000 | 0.500012618 | 1.26e-05 |
| 45° | 0.707106781 | 0.707095801 | 1.10e-05 | 0.707106781 | 0.707117761 | 1.10e-05 |
| 60° | 0.500000000 | 0.500012618 | 1.26e-05 | 0.866025404 | 0.866018117 | 7.29e-06 |
| 90° | 0.000000000 | -0.000017593 | 1.76e-05 | 1.000000000 | 0.999999998 | 1.86e-09 |

El error máximo es **1.76e-05**, dentro de lo predicho por `arctan(2^-15)`.

## Compensación de ganancia

CORDIC alarga el vector en cada iteración. Tras N pasos la ganancia acumulada es

```
K_N = prod( sqrt(1 + 2^-2i) ,  i = 0..N-1 )
```

Para N = 16: `K₁₆` = 1.646760258, de donde `1/K₁₆` = 0.607252935.

Inicializando `x₀ = 1/K₁₆` la ganancia se cancela sola y no hace falta
multiplicar al final. En Q2.30 esa constante es `round(0.607252935 * 2^30)` =
**652032874**.

## Convergencia

El algoritmo converge mientras el ángulo esté dentro de la suma de todos los
ángulos de la tabla:

```
|θ| <= Σ arctan(2^-i) = 1.7433 rad = 99.88°
```

Los ángulos que pide el enunciado (0° a 90°) están dentro del rango, por lo que
no se implementó pre-rotación de cuadrante. Para ángulos fuera de ±99.88° haría
falta una etapa previa que los reduzca al primer cuadrante.

## Máquina de estados

El módulo `cordic.v` se controla con una FSM de cuatro estados:

```
        ┌──────┐  start   ┌──────┐          ┌─────────┐  i = 15   ┌──────┐
        │ IDLE ├─────────►│ INIT ├─────────►│ ITERATE ├──────────►│ DONE │
        └──────┘          └──────┘          └────┬────┘           └───┬──┘
            ▲                  ▲                 │ i < 15             │
            │                  │                 └────────────────────┘
            │                  └───────────────── start ──────────────┘
            └─ reset
```

- **IDLE** — espera `start`. Conserva el resultado de la operación anterior.
- **INIT** — carga `x₀ = 1/K₁₆`, `y₀ = 0`, `z₀ = θ` y pone el contador en 0.
- **ITERATE** — una iteración por ciclo de reloj, 16 en total.
- **DONE** — levanta `done` y mantiene el resultado hasta el siguiente `start`.

**Latencia: 18 ciclos** desde `start` — uno para entrar a INIT, otro para entrar
a ITERATE y 16 de iteración.

Las ecuaciones que ejecuta cada iteración:

```
x[i+1] = x[i] - d[i] * (y[i] >>> i)
y[i+1] = y[i] + d[i] * (x[i] >>> i)
z[i+1] = z[i] - d[i] * arctan(2^-i)
```

El sentido de rotación `d[i]` sale directo del **bit de signo de z**
(`z_reg[31]`): si `z >= 0` se rota en `+1`, si no en `-1`. No hace falta un
comparador, el bit de signo *es* la decisión.

## Interfaz de los módulos

### `cordic.v`

| Señal | Dir | Descripción |
|---|---|---|
| `clk`, `reset` | in | Reloj y reset síncrono activo en alto |
| `start` | in | Pulso de inicio |
| `angle` | in | θ en radianes, Q2.30 |
| `cos_out`, `sin_out` | out | Resultados en Q2.30 |
| `done` | out | 1 cuando el resultado es válido |

### `alu32.v`

Añade a las operaciones convencionales una operación CORDIC multiciclo. El
ángulo entra por `A`, el coseno sale por `Result` y el seno por `Result_hi`.

| OP | Operación | OP | Operación |
|---|---|---|---|
| `0000` | `A + B` | `0101` | `A << B[4:0]` |
| `0001` | `A - B` | `0110` | `A >> B[4:0]` (lógico) |
| `0010` | `A & B` | `0111` | `A >>> B[4:0]` (aritmético) |
| `0011` | `A \| B` | `1000` | `A < B` con signo |
| `0100` | `A ^ B` | `1001` | **CORDIC** (multiciclo) |

Las operaciones combinacionales terminan en el mismo ciclo y mantienen `done`
en alto. La CORDIC mantiene `busy` durante 18 ciclos y levanta `done` al
terminar; mientras `busy` está activo se ignoran nuevos `start`.

Flags: `Zero` y `Negative` se derivan de `Result` y valen para toda operación.
`Carry` y `Overflow` solo tienen sentido en ADD y SUB, y valen 0 en el resto.
En SUB, `Carry` sigue el convenio de RISC-V/ARM: 1 significa que *no* hubo
préstamo.

## Versión RISC-V

`cordic.s` implementa el mismo algoritmo en RV32I, sin instrucciones de punto
flotante ni la extensión M.

La subrutina `cordic` recibe `a0` = dirección del coseno, `a1` = dirección del
seno y `a2` = ángulo en Q2.30. Usa únicamente `t0`–`t6`, así que no necesita
guardar nada en la pila:

| Registro | Uso |
|---|---|
| `t0`, `t1`, `t2` | `x`, `y`, `z` |
| `t3` | contador de iteraciones |
| `t4` | puntero a `atan_table[i]` |
| `t5`, `t6` | temporales (términos desplazados y `alpha_i`) |

Los desplazamientos usan `sra`, que replica el bit de signo — es lo que exige
el algoritmo para operar con valores negativos. `srl` daría resultados
incorrectos en cuanto `x` o `y` se vuelvan negativos.

El programa principal recorre los mismos cinco ángulos del testbench de
Verilog, llama a la subrutina, y compara cada resultado contra el valor ideal
con una tolerancia de `2^-13` = 1.22e-04, acumulando el total en
`error_count`. La ejecución completa toma **1220 instrucciones** para los cinco
casos, unas 244 por ángulo.

## Comparación hardware vs. software

| | Hardware (`cordic.v`) | Software (`cordic.s`) |
|---|---|---|
| Latencia por ángulo | 18 ciclos | ~244 instrucciones |
| Error máximo | 1.76e-05 | 1.76e-05 (idéntico bit a bit) |
| Recursos | 3 sumadores/restadores, 3 registros, ROM de 16 palabras | ninguno adicional |

El acelerador es aproximadamente **un orden de magnitud más rápido** y no
ocupa el pipeline del procesador. Ambas versiones dan exactamente los mismos
bits porque usan el mismo formato, la misma tabla y el mismo orden de
operaciones.
