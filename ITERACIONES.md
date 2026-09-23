# Traza completa del algoritmo CORDIC

Las 16 iteraciones para `theta = 30 grados`, a nivel de bits, tal como las
ejecuta el hardware (`cordic.v`) y la subrutina en RISC-V (`cordic.s`).

Ambas implementaciones producen exactamente estos mismos bits.

---

## 1. Representacion: Q2.30 con signo

```
 bit  31  30 | 29  28  27  26 ...  1   0
     +---+---+---+---+---+---+---+---+---+
peso | -2| +1| 1/2|1/4|1/8|      |   |2^-30
     +---+---+---+---+---+---+---+---+---+
       ^      ^
       |      +-- punto binario
       +--------- signo (complemento a 2)
```

| Parametro | Valor |
|---|---|
| Bits totales | 32 |
| Parte entera | 2 (1 de signo + 1 de magnitud) |
| Parte fraccionaria | 30 |
| Rango | `[-2.0, +2.0)` |
| LSB | `2^-30` |

En la notacion `SI.FFFF...` de este documento: `S` es el signo, `I` la parte
entera, y los 30 bits tras el punto la fraccion.

El valor real es `entero / 2^30`. Nada mas: el hardware nunca *sabe* que hay
un punto binario, opera con enteros de 32 bits en complemento a 2.

## 2. Constantes

```
x0 = 1/K16   00.100110110111010011101101101010
y0 = 0       00.000000000000000000000000000000
z0 = 30 deg  00.100001100000101010010001110000
```

`K16 = 1.646760258` es la ganancia que el algoritmo acumula en 16 pasos.
Arrancando en `x0 = 1/K16` se cancela sola y no hay que multiplicar al final.

## 3. Tabla de angulos

`alpha[i] = arctan(2^-i)` en Q2.30.

| i | binario | grados |
|---|---|---|
|  0 | `00.110010010000111111011010101001` | 45.000000 |
|  1 | `00.011101101011000110011100000101` | 26.565051 |
|  2 | `00.001111101011011011101011111101` | 14.036243 |
|  3 | `00.000111111101010110111010100111` |  7.125016 |
|  4 | `00.000011111111101010101101110111` |  3.576334 |
|  5 | `00.000001111111111101010101011100` |  1.789911 |
|  6 | `00.000000111111111111101010101011` |  0.895174 |
|  7 | `00.000000011111111111111101010101` |  0.447614 |
|  8 | `00.000000001111111111111111101011` |  0.223811 |
|  9 | `00.000000000111111111111111111101` |  0.111906 |
| 10 | `00.000000000100000000000000000000` |  0.055953 |
| 11 | `00.000000000010000000000000000000` |  0.027976 |
| 12 | `00.000000000001000000000000000000` |  0.013988 |
| 13 | `00.000000000000100000000000000000` |  0.006994 |
| 14 | `00.000000000000010000000000000000` |  0.003497 |
| 15 | `00.000000000000001000000000000000` |  0.001749 |

Desde `i = 10` las entradas son potencias de 2 exactas, un solo bit encendido,
porque `arctan(v) ~ v` cuando `v` es pequeno.

## 4. El algoritmo

En cada iteracion, el signo de `z` decide la direccion:

```
si z >= 0  (z[31] = 0)  ->  d = +1  ->  estado S_ROT_POS
    x <- x - (y >>> i)
    y <- y + (x >>> i)
    z <- z - alpha[i]

si z <  0  (z[31] = 1)  ->  d = -1  ->  estado S_ROT_NEG
    x <- x + (y >>> i)
    y <- y - (x >>> i)
    z <- z + alpha[i]
```

Los desplazamientos son **aritmeticos** (`>>>`, `sra`): replican el bit de
signo. Con desplazamiento logico el algoritmo se rompe en cuanto `x` o `y`
se vuelven negativos.

`y` se actualiza con el `x` **viejo**, asi que ambos desplazamientos se
calculan antes de escribir nada.

---

## 5. Una iteracion explicada

Tomamos `i = 1` como modelo. Es la primera con desplazamiento real.

**Estado al entrar:**

```
x  00.100110110111010011101101101010
y  00.100110110111010011101101101010
z  11.101111001111101010110111000111
```

**Paso 1 - decidir.** El bit 31 de `z` vale 1, o sea `z < 0`: nos pasamos en
el paso anterior (giramos 45 grados queriendo 30). Hay que volver, `d = -1`.
En complemento a 2 el bit de signo *es* la decision: ni comparador ni resta.

**Paso 2 - desplazar.** `alpha[1]` cumple `tan(alpha) = 2^-1`, asi que
multiplicar por la tangente es correr **un bit**:

```
x        00.100110110111010011101101101010
x >>> 1  00.010011011011101001110110110101
         ^
         entra una copia del bit 31 (aqui 0, porque x es positivo)
```

Ahi es donde CORDIC se ahorra el multiplicador.

**Paso 3 - operar.** Con `d = -1` los signos se invierten:

```
x = x + (y>>>1):   00.100110110111010011101101101010
                 + 00.010011011011101001110110110101
                 = 00.111010010010111101100100011111

y = y - (x>>>1):   00.100110110111010011101101101010
                 - 00.010011011011101001110110110101
                 = 00.010011011011101001110110110101

z = z + alpha[1]:  11.101111001111101010110111000111
                 + 00.011101101011000110011100000101
                 = 00.001100111010110001010011001100
```

Las restas usan el mismo sumador: se invierte el operando y se mete 1 por el
acarreo de entrada. No existe circuito restador.

**Verificacion.** El resultado cumple `x = 3y`, comprobable con un corrimiento
y una suma:

```
y        00.010011011011101001110110110101
2y       00.100110110111010011101101101010   (correr y un bit a la izquierda)
2y + y   00.111010010010111101100100011111   = x   OK
```

Entonces la direccion del punto es `arctan(y/x) = arctan(1/3)`. Veniamos de
`arctan(1) = 45 grados`, asi que el giro fue:

```
arctan(1) - arctan(1/3) = arctan(1/2) = alpha[1]    OK

porque  tan(45 - phi) = (1 - 1/3)/(1 + 1/3) = 1/2
```

**Giramos exactamente el angulo de la tabla, con una suma, una resta y dos
corrimientos.** Eso es toda la iteracion.

---

## 6. Las 16 iteraciones

### Correspondencia con los ciclos de reloj

Cada iteracion ocupa **un ciclo** y se ejecuta dentro de un estado de
rotacion. El mapeo, tomado de la simulacion:

```
ciclo  1   S_INIT       carga x0, y0, z0, iter=0
ciclo  2   S_ROT_*      iteracion i=0
ciclo  3   S_ROT_*      iteracion i=1
  ...
ciclo 17   S_ROT_*      iteracion i=15
ciclo 18   S_DONE       done=1, resultado disponible
```

O sea: **la iteracion `i` corre en el ciclo `i + 2`**. Total 18 ciclos desde
`start`, que es la latencia del acelerador.

### Como se elige el estado siguiente

El estado en que corre la iteracion `i` codifica `d[i]`. Ese estado se decidio
**durante la iteracion anterior**, mirando el signo de `z_next`, o sea el
residual que `z` va a tener en el ciclo siguiente:

```
z_next[31] = 0  ->  siguiente estado = S_ROT_POS   (d = +1)
z_next[31] = 1  ->  siguiente estado = S_ROT_NEG   (d = -1)

excepto saliendo de S_INIT, donde z aun no se ha cargado y
el bit que manda es angle[31].

y en iter = 15, donde la transicion va a S_DONE sin mirar el signo.
```

Por eso en cada bloque de abajo aparecen dos estados: el que **ejecuta** la
iteracion, y el que queda **seleccionado** para la siguiente.

---

### i = 0  |  ciclo 2  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 0 bits

```
           antes                              despues
x  00.100110110111010011101101101010  ->  00.100110110111010011101101101010
y  00.000000000000000000000000000000  ->  00.100110110111010011101101101010
z  00.100001100000101010010001110000  ->  11.101111001111101010110111000111

x >>> 0    00.100110110111010011101101101010
y >>> 0    00.000000000000000000000000000000
alpha[ 0]  00.110010010000111111011010101001
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 3)

---

### i = 1  |  ciclo 3  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 1 bit

```
           antes                              despues
x  00.100110110111010011101101101010  ->  00.111010010010111101100100011111
y  00.100110110111010011101101101010  ->  00.010011011011101001110110110101
z  11.101111001111101010110111000111  ->  00.001100111010110001010011001100

x >>> 1    00.010011011011101001110110110101
y >>> 1    00.010011011011101001110110110101
alpha[ 1]  00.011101101011000110011100000101
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 4)

---

### i = 2  |  ciclo 4  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 2 bits

```
           antes                              despues
x  00.111010010010111101100100011111  ->  00.110101011100000011000110110010
y  00.010011011011101001110110110101  ->  00.100010000000011001001111111100
z  00.001100111010110001010011001100  ->  11.111101001111010101100111001111

x >>> 2    00.001110100100101111011001000111
y >>> 2    00.000100110110111010011101101101
alpha[ 2]  00.001111101011011011101011111101
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 5)

---

### i = 3  |  ciclo 5  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 3 bits

```
           antes                              despues
x  00.110101011100000011000110110010  ->  00.111001101100000110010000110001
y  00.100010000000011001001111111100  ->  00.011011010100111000110111000110
z  11.111101001111010101100111001111  ->  00.000101001100101100100001110110

x >>> 3    00.000110101011100000011000110110
y >>> 3    00.000100010000000011001001111111
alpha[ 3]  00.000111111101010110111010100111
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 6)

---

### i = 4  |  ciclo 6  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 4 bits

```
           antes                              despues
x  00.111001101100000110010000110001  ->  00.110111111110110010101101010101
y  00.011011010100111000110111000110  ->  00.011110111011101001010000001001
z  00.000101001100101100100001110110  ->  00.000001001101000001110011111111

x >>> 4    00.000011100110110000011001000011
y >>> 4    00.000001101101010011100011011100
alpha[ 4]  00.000011111111101010101101110111
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 7)

---

### i = 5  |  ciclo 7  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 5 bits

```
           antes                              despues
x  00.110111111110110010101101010101  ->  00.110111000000111011011010110101
y  00.011110111011101001010000001001  ->  00.100000101011100110110101100011
z  00.000001001101000001110011111111  ->  11.111111001101000100011110100011

x >>> 5    00.000001101111111101100101011010
y >>> 5    00.000000111101110111010010100000
alpha[ 5]  00.000001111111111101010101011100
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 8)

---

### i = 6  |  ciclo 8  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 6 bits

```
           antes                              despues
x  00.110111000000111011011010110101  ->  00.110111100001100111000001101010
y  00.100000101011100110110101100011  ->  00.011111110100100101111010001001
z  11.111111001101000100011110100011  ->  00.000000001101000100001001001110

x >>> 6    00.000000110111000000111011011010
y >>> 6    00.000000100000101011100110110101
alpha[ 6]  00.000000111111111111101010101011
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 9)

---

### i = 7  |  ciclo 9  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 7 bits

```
           antes                              despues
x  00.110111100001100111000001101010  ->  00.110111010001101100101110101101
y  00.011111110100100101111010001001  ->  00.100000010000010110101101101001
z  00.000000001101000100001001001110  ->  11.111111101101000100001011111001

x >>> 7    00.000000011011110000110011100000
y >>> 7    00.000000001111111010010010111101
alpha[ 7]  00.000000011111111111111101010101
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 10)

---

### i = 8  |  ciclo 10  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 8 bits

```
           antes                              despues
x  00.110111010001101100101110101101  ->  00.110111011001110000110100011000
y  00.100000010000010110101101101001  ->  00.100000000010100010010010011110
z  11.111111101101000100001011111001  ->  11.111111111101000100001011100100

x >>> 8    00.000000001101110100011011001011
y >>> 8    00.000000001000000100000101101011
alpha[ 8]  00.000000001111111111111111101011
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 11)

---

### i = 9  |  ciclo 11  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 9 bits

```
           antes                              despues
x  00.110111011001110000110100011000  ->  00.110111011101110001001000101010
y  00.100000000010100010010010011110  ->  00.011111111011100111000100011000
z  11.111111111101000100001011100100  ->  00.000000000101000100001011100001

x >>> 9    00.000000000110111011001110000110
y >>> 9    00.000000000100000000010100010010
alpha[ 9]  00.000000000111111111111111111101
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 12)

---

### i = 10  |  ciclo 12  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 10 bits

```
           antes                              despues
x  00.110111011101110001001000101010  ->  00.110111011011110001011010001110
y  00.011111111011100111000100011000  ->  00.011111111111000100111011011100
z  00.000000000101000100001011100001  ->  00.000000000001000100001011100001

x >>> 10   00.000000000011011101110111000100
y >>> 10   00.000000000001111111101110011100
alpha[10]  00.000000000100000000000000000000
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 13)

---

### i = 11  |  ciclo 13  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 11 bits

```
           antes                              despues
x  00.110111011011110001011010001110  ->  00.110111011010110001011100000101
y  00.011111111111000100111011011100  ->  00.100000000000110011110010111110
z  00.000000000001000100001011100001  ->  11.111111111111000100001011100001

x >>> 11   00.000000000001101110110111100010
y >>> 11   00.000000000000111111111110001001
alpha[11]  00.000000000010000000000000000000
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 14)

---

### i = 12  |  ciclo 14  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 12 bits

```
           antes                              despues
x  00.110111011010110001011100000101  ->  00.110111011011010001011100111000
y  00.100000000000110011110010111110  ->  00.011111111111111100011000001101
z  11.111111111111000100001011100001  ->  00.000000000000000100001011100001

x >>> 12   00.000000000000110111011010110001
y >>> 12   00.000000000000100000000000110011
alpha[12]  00.000000000001000000000000000000
```

`z_next[31] = 0`  ->  siguiente estado: **`S_ROT_POS`**  (ciclo 15)

---

### i = 13  |  ciclo 15  |  estado `S_ROT_POS`

`z[31] = 0`  ->  `d = +1`  ->  desplazamiento de 13 bits

```
           antes                              despues
x  00.110111011011010001011100111000  ->  00.110111011011000001011100111010
y  00.011111111111111100011000001101  ->  00.100000000000011000000101110101
z  00.000000000000000100001011100001  ->  11.111111111111100100001011100001

x >>> 13   00.000000000000011011101101101000
y >>> 13   00.000000000000001111111111111110
alpha[13]  00.000000000000100000000000000000
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 16)

---

### i = 14  |  ciclo 16  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 14 bits

```
           antes                              despues
x  00.110111011011000001011100111010  ->  00.110111011011001001011101000000
y  00.100000000000011000000101110101  ->  00.100000000000001010001111000101
z  11.111111111111100100001011100001  ->  11.111111111111110100001011100001

x >>> 14   00.000000000000001101110110110000
y >>> 14   00.000000000000001000000000000110
alpha[14]  00.000000000000010000000000000000
```

`z_next[31] = 1`  ->  siguiente estado: **`S_ROT_NEG`**  (ciclo 17)

---

### i = 15  |  ciclo 17  |  estado `S_ROT_NEG`

`z[31] = 1`  ->  `d = -1`  ->  desplazamiento de 15 bits

```
           antes                              despues
x  00.110111011011001001011101000000  ->  00.110111011011001101011101000001
y  00.100000000000001010001111000101  ->  00.100000000000000011010011101100
z  11.111111111111110100001011100001  ->  11.111111111111111100001011100001

x >>> 15   00.000000000000000110111011011001
y >>> 15   00.000000000000000100000000000001
alpha[15]  00.000000000000001000000000000000
```

`iter = 15`, ultima iteracion: la FSM transiciona a **`S_DONE`** sin mirar
el signo. Los resultados se publican en `cos_out` y `sin_out` en este mismo
flanco, asi que ya estan validos cuando `done` sube.

## 7. Salida

```
cos_out  00.110111011011001101011101000001
sin_out  00.100000000000000011010011101100
z final  11.111111111111111100001011100001
```

**Leyendo `sin_out` directamente en bits:**

```
sin_out  00.100000000000000011010011101100
            ^  +------------+
            |       14 ceros
            +-- bit 29, peso 1/2
```

El primer bit de fraccion encendido y luego catorce ceros: es `1/2` con una
correccion por debajo de `2^-15`. No hace falta convertir nada, el patron lo
dice. Y `2^-15` es justo el limite de precision de 16 iteraciones.

**El residual `z`:**

```
z final  11.111111111111111100001011100001
         +---------------+
           18 bits de signo
```

Negativo y diminuto: 18 bits de signo seguidos antes del primer bit distinto.
Lo que garantiza el algoritmo es que este residual quede por debajo del ultimo
angulo de la tabla, `alpha[15] = 2^-15`, y asi es. Ese es el limite de
precision de 16 iteraciones (ver seccion 8).

**Equivalente decimal** (solo como comprobacion externa):

| | Obtenido | Real | Error |
|---|---|---|---|
| `cos 30` | 0.866018117 | 0.866025404 | 7.29e-06 |
| `sin 30` | 0.500012618 | 0.500000000 | 1.26e-05 |

La magnitud del vector final es `0.999999999`: la ganancia `K16` quedo
compensada, el punto cayo sobre el circulo unitario.

## 8. Resumen del recorrido

```
i:          0    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15
z[31]:      0    1    0    1    0    0    1    0    1    1    0    0    1    0    1    1
rama:     POS  NEG  POS  NEG  POS  POS  NEG  POS  NEG  NEG  POS  POS  NEG  POS  NEG  NEG
```

No es un zigzag limpio: hay `POS POS` en i=4,5 y `NEG NEG` en i=8,9. Eso
confirma que la direccion la decide el signo del residual en cada paso, no un
patron fijo.

### Como converge el residual

La garantia del algoritmo **no** es que `|z|` baje en cada paso, sino que
despues de la iteracion `i` el residual queda acotado por el angulo que
acaba de usarse:

```
|z| < alpha[i]
```

Como `alpha[i]` se reduce a la mitad en cada paso, la **cota** se parte por
dos cada iteracion, y eso es lo que fuerza la convergencia.

| i | `z` despues | `alpha[i]` | `\|z\| < alpha[i]` |
|---|---|---|---|
|  0 | `  -281104953` | ` 843314857` | si |
|  1 | `   216732876` | ` 497837829` | si |
|  2 | `   -46310961` | ` 263043837` | si |
|  3 | `    87214198` | ` 133525159` | si |
|  4 | `    20192511` | `  67021687` | si |
|  5 | `   -13351005` | `  33543516` | si |
|  6 | `     3424846` | `  16775851` | si |
|  7 | `    -4963591` | `   8388437` | si |
|  8 | `     -769308` | `   4194283` | si |
|  9 | `     1327841` | `   2097149` | si |
| 10 | `      279265` | `   1048576` | si |
| 11 | `     -245023` | `    524288` | si |
| 12 | `       17121` | `    262144` | si |
| 13 | `     -113951` | `    131072` | si |
| 14 | `      -48415` | `     65536` | si |
| 15 | `      -15647` | `     32768` | si |

**`z` rebota, y es normal.** En `i = 12` el residual baja a `17121`, pero en
`i = 13` sube a `113951`. Eso pasa porque cada giro es de tamano fijo: si te
quedas muy cerca del objetivo, el siguiente paso obligatoriamente te pasa al
otro lado. Lo que nunca crece es la cota.

En bits se ve asi: el residual siempre cabe dentro del hueco que deja
`alpha[i]`, aunque su patron concreto suba y baje.

```
i=10  z      00.000000000001000100001011100001
      alpha  00.000000000100000000000000000000

i=11  z      11.111111111111000100001011100001
      alpha  00.000000000010000000000000000000

i=12  z      00.000000000000000100001011100001
      alpha  00.000000000001000000000000000000

i=13  z      11.111111111111100100001011100001
      alpha  00.000000000000100000000000000000

i=14  z      11.111111111111110100001011100001
      alpha  00.000000000000010000000000000000

i=15  z      11.111111111111111100001011100001
      alpha  00.000000000000001000000000000000

```

Tras 16 iteraciones la cota es `alpha[15] = 2^-15`, y de ahi sale la regla
`N - 1`: con `N` iteraciones obtienes del orden de `N - 1` bits utiles.
Seguir iterando solo ayuda hasta que `alpha[i]` llega a cero en la tabla
(en Q2.30 eso ocurre en `i = 31`), y antes de eso el error de truncamiento
acumulado de los desplazamientos ya domina.
