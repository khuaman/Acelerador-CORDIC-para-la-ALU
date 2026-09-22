#=============================================================================
# cordic.s -- Algoritmo CORDIC (modo rotacion) en Assembly RISC-V RV32I
#
# Version software del acelerador hardware de cordic.v. Calcula el seno y el
# coseno de un angulo usando unicamente sumas, restas, desplazamientos,
# comparaciones y accesos a memoria. No se usa ninguna instruccion de punto
# flotante ni la extension M.
#
# -----------------------------------------------------------------------------
# REPRESENTACION: Q2.30 con signo, identica a la del hardware
# -----------------------------------------------------------------------------
#   32 bits totales = 2 enteros (1 de signo) + 30 fraccionarios
#   Rango [-2.0, +2.0)   LSB = 2^-30 = 9.3132e-10
#   Para convertir: valor_fijo = round(valor_real * 2^30)
#
#   N = 16 iteraciones  ->  K16 = 1.646760258,  1/K16 = 0.607252935
#   x0 = round(0.607252935 * 2^30) = 652032874
#
#   Convergencia garantizada para |theta| <= 1.7433 rad = 99.88 grados.
#
# -----------------------------------------------------------------------------
# NOTA SOBRE PSEUDOINSTRUCCIONES
# -----------------------------------------------------------------------------
#   Se usan li, la, mv, j, ret, bltz y bgez por legibilidad. Todas son
#   pseudoinstrucciones que el ensamblador expande a instrucciones RV32I
#   reales (lui/addi, auipc/addi, jal x0, jalr x0 ra 0, blt/bge contra x0),
#   asi que no se sale del subconjunto permitido.
#=============================================================================

                .data

#-----------------------------------------------------------------------------
# Tabla de angulos: alpha_i = arctan(2^-i) en Q2.30
#-----------------------------------------------------------------------------
                .align 2
atan_table:     .word 843314857         # i= 0  0.785398163 rad = 45.000000 deg
                .word 497837829         # i= 1  0.463647609 rad = 26.565051 deg
                .word 263043837         # i= 2  0.244978663 rad = 14.036243 deg
                .word 133525159         # i= 3  0.124354995 rad =  7.125016 deg
                .word 67021687          # i= 4  0.062418810 rad =  3.576334 deg
                .word 33543516          # i= 5  0.031239833 rad =  1.789911 deg
                .word 16775851          # i= 6  0.015623729 rad =  0.895174 deg
                .word 8388437           # i= 7  0.007812341 rad =  0.447614 deg
                .word 4194283           # i= 8  0.003906230 rad =  0.223811 deg
                .word 2097149           # i= 9  0.001953123 rad =  0.111906 deg
                .word 1048576           # i=10  0.000976562 rad =  0.055953 deg
                .word 524288            # i=11  0.000488281 rad =  0.027976 deg
                .word 262144            # i=12  0.000244141 rad =  0.013988 deg
                .word 131072            # i=13  0.000122070 rad =  0.006994 deg
                .word 65536             # i=14  0.000061035 rad =  0.003497 deg
                .word 32768             # i=15  0.000030518 rad =  0.001749 deg

#-----------------------------------------------------------------------------
# Angulos de prueba (los mismos que valida el testbench de Verilog)
#-----------------------------------------------------------------------------
                .align 2
angles:         .word 0                 #  0 grados
                .word 562209904         # 30 grados
                .word 843314857         # 45 grados
                .word 1124419809        # 60 grados
                .word 1686629713        # 90 grados

# Valores ideales en Q2.30, para comparar
cos_expected:   .word 1073741824, 929887697, 759250125, 536870912, 0
sin_expected:   .word 0, 536870912, 759250125, 929887697, 1073741824

#-----------------------------------------------------------------------------
# Espacio reservado para los resultados
#-----------------------------------------------------------------------------
                .align 2
cos_result:     .space 20               # 5 palabras
sin_result:     .space 20               # 5 palabras
error_count:    .word 0                 # comprobaciones fuera de tolerancia

                .text
                .globl main

#=============================================================================
# main -- programa principal
#
# 1. Recorre la lista de angulos de prueba.
# 2. Invoca cordic para cada uno, guardando los resultados en memoria.
# 3. Recupera los valores y los compara contra los esperados.
# 4. Acumula en error_count las comprobaciones que salen de tolerancia.
#
# Registros: s0..s7 mantienen punteros e indices a lo largo de todo main.
#=============================================================================
main:
                la      s0, angles              # s0 = base de los angulos
                la      s1, cos_result          # s1 = base de los cosenos
                la      s2, sin_result          # s2 = base de los senos
                li      s3, 0                   # s3 = indice del caso
                li      s4, 5                   # s4 = numero de casos

#--- Fase 1: calcular -------------------------------------------------------
calc_loop:
                bge     s3, s4, calc_done

                slli    t0, s3, 2               # t0 = indice * 4 (bytes)
                add     t1, s0, t0
                lw      a2, 0(t1)               # a2 = angulo de entrada
                add     a0, s1, t0              # a0 = &cos_result[i]
                add     a1, s2, t0              # a1 = &sin_result[i]

                jal     ra, cordic

                addi    s3, s3, 1
                j       calc_loop
calc_done:

#--- Fase 2: verificar ------------------------------------------------------
                la      s6, cos_expected
                la      s7, sin_expected
                li      s3, 0                   # reinicia el indice
                li      s5, 0                   # s5 = contador de errores

check_loop:
                bge     s3, s4, check_done
                slli    t0, s3, 2

                # --- coseno: |obtenido - esperado| < tolerancia ---
                add     t1, s1, t0
                lw      t2, 0(t1)               # t2 = obtenido
                add     t1, s6, t0
                lw      t3, 0(t1)               # t3 = esperado
                sub     t4, t2, t3              # t4 = diferencia
                bgez    t4, cos_abs_ok
                sub     t4, zero, t4            # valor absoluto
cos_abs_ok:
                li      t5, 131072              # tolerancia 2^-13 = 1.22e-04
                blt     t4, t5, cos_in_range
                addi    s5, s5, 1
cos_in_range:

                # --- seno: mismo criterio ---
                add     t1, s2, t0
                lw      t2, 0(t1)
                add     t1, s7, t0
                lw      t3, 0(t1)
                sub     t4, t2, t3
                bgez    t4, sin_abs_ok
                sub     t4, zero, t4
sin_abs_ok:
                li      t5, 131072
                blt     t4, t5, sin_in_range
                addi    s5, s5, 1
sin_in_range:

                addi    s3, s3, 1
                j       check_loop
check_done:

                la      t0, error_count
                sw      s5, 0(t0)               # guarda el total de errores

                li      a7, 10                  # syscall exit
                ecall

#=============================================================================
# cordic -- calcula cos(theta) y sin(theta) por rotacion iterativa
#
# Parametros:
#   a0 = direccion donde se almacena el coseno
#   a1 = direccion donde se almacena el seno
#   a2 = angulo theta en radianes, formato Q2.30
#
# Retorno:
#   Escribe dos palabras en memoria. No modifica ningun registro s.
#   Usa solo t0..t6, que son de uso libre segun la convencion de llamada.
#
# Registros internos:
#   t0 = x      t1 = y      t2 = z      t3 = i (contador)
#   t4 = puntero a atan_table[i]        t5, t6 = temporales
#=============================================================================
cordic:
                #--- Inicializacion: x0 = 1/K16, y0 = 0, z0 = theta ---
                li      t0, 652032874           # x = 1/K16 = 0.607252935
                li      t1, 0                   # y = 0
                mv      t2, a2                  # z = theta
                li      t3, 0                   # i = 0
                la      t4, atan_table          # t4 = &atan_table[0]

cordic_loop:
                li      t5, 16                  # N = 16 iteraciones
                bge     t3, t5, cordic_end

                #--- Terminos desplazados: x >>> i  e  y >>> i ---
                # sra replica el bit de signo, que es lo que exige el
                # algoritmo para operar con valores negativos.
                sra     t5, t0, t3              # t5 = x >>> i
                sra     t6, t1, t3              # t6 = y >>> i

                #--- Sentido de la rotacion segun el signo de z ---
                bltz    t2, cordic_neg          # z < 0  ->  d = -1

                #--- d = +1 ---
                sub     t0, t0, t6              # x = x - (y >>> i)
                add     t1, t1, t5              # y = y + (x >>> i)
                lw      t5, 0(t4)               # t5 = alpha_i
                sub     t2, t2, t5              # z = z - alpha_i
                j       cordic_next

                #--- d = -1 ---
cordic_neg:
                add     t0, t0, t6              # x = x + (y >>> i)
                sub     t1, t1, t5              # y = y - (x >>> i)
                lw      t5, 0(t4)               # t5 = alpha_i
                add     t2, t2, t5              # z = z + alpha_i

cordic_next:
                addi    t3, t3, 1               # i = i + 1
                addi    t4, t4, 4               # avanza a alpha_{i+1}
                j       cordic_loop

cordic_end:
                #--- Tras 16 iteraciones: x ~= cos(theta), y ~= sin(theta) ---
                sw      t0, 0(a0)
                sw      t1, 0(a1)
                ret
