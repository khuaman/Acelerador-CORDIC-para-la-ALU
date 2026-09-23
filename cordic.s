                .data

# Tabla de angulos: alpha_i = arctan(2^-i)

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


# Angulos de prueba

                .align 2
angles:         .word 0                 #  0 grados
                .word 562209904         # 30 grados
                .word 843314857         # 45 grados
                .word 1124419809        # 60 grados
                .word 1686629713        # 90 grados

# Valores ideales/esperados para comparar
cos_expected:   .word 1073741824, 929887697, 759250125, 536870912, 0
sin_expected:   .word 0, 536870912, 759250125, 929887697, 1073741824


# Espacio reservado para los resultados

                .align 2
cos_result:     .space 20     # 5 palabras para cos(0), cos(30), ...          
sin_result:     .space 20     # 5 palabras para sin(0), sin(30), ...          
error_count:    .word 0                 

                .text
                .globl main


# Programa principal
# 1. Recorre la lista de 5 angulos de prueba (0°, 30°, 45°, 60°, 90°).
# 2. Invoca cordic para cada uno, guardando los resultados en memoria.
# 3. Recupera los valores y los compara contra los esperados.
# 4. Acumula en error_count las comprobaciones que salen de tolerancia.

# Registros: s0..s7 mantienen punteros e indices a lo largo de todo main.


main:
                la      s0, angles              # s0 = base de los angulos
                la      s1, cos_result          # s1 = base de los cosenos
                la      s2, sin_result          # s2 = base de los senos
                addi    s3, zero, 0             # s3 = indice del caso (0)
                addi    s4, zero, 5             # s4 = numero de casos (5)

# Calcular
calc_loop:
                bge     s3, s4, calc_done

                slli    t0, s3, 2               # t0 = indice * 4 (bytes)
                add     t1, s0, t0
                lw      a2, 0(t1)               # a2 = angulo de entrada
                add     a0, s1, t0              # a0 = &cos_result[i]
                add     a1, s2, t0              # a1 = &sin_result[i]

                jal     ra, cordic

                addi    s3, s3, 1
                jal     zero, calc_loop
calc_done:
# Verificar
                la      s6, cos_expected
                la      s7, sin_expected
                addi    s3, zero, 0             # reinicia el indice
                addi    s5, zero, 0             # s5 = contador de errores

check_loop:
                bge     s3, s4, check_done
                slli    t0, s3, 2

                # coseno: |obtenido - esperado| < tolerancia
                add     t1, s1, t0
                lw      t2, 0(t1)               # t2 = obtenido
                add     t1, s6, t0
                lw      t3, 0(t1)               # t3 = esperado
                sub     t4, t2, t3              # t4 = diferencia
                bge     t4, zero, cos_abs_ok
                sub     t4, zero, t4            # valor absoluto
cos_abs_ok:
                lui     t5, 32                  # tolerancia 131072 (2^-13 = 1.22e-04)
                blt     t4, t5, cos_in_range
                addi    s5, s5, 1
cos_in_range:

                #  seno: mismo criterio
                add     t1, s2, t0
                lw      t2, 0(t1)
                add     t1, s7, t0
                lw      t3, 0(t1)
                sub     t4, t2, t3
                bge     t4, zero, sin_abs_ok
                sub     t4, zero, t4
sin_abs_ok:
                lui     t5, 32                  # tolerancia 131072
                blt     t4, t5, sin_in_range
                addi    s5, s5, 1
sin_in_range:

                addi    s3, s3, 1
                jal     zero, check_loop
check_done:

                la      t0, error_count
                sw      s5, 0(t0)               # guarda el total de errores

                addi    a7, zero, 10            # syscall exit
                ecall



# Logica del CORDIC (calcula cos y sin)

# Parametros:
#   a0 = direccion donde se almacena el coseno
#   a1 = direccion donde se almacena el seno
#   a2 = angulo theta en radianes, formato Q2.30

# Retorno:
#   Escribe dos palabras en memoria. No modifica ningun registro s.
#   Usa solo t0..t6, que son de uso libre segun la convencion de llamada.

# Registros internos:
#   t0 = x      t1 = y      t2 = z      t3 = i (contador)
#   t4 = puntero a atan_table[i]        t5, t6 = temporales

cordic:
                lui     t0, 159188              # 159188 = 0x26DD4
                addi    t0, t0, -1174           # (159188 << 12) - 1174 = 652032874
                addi    t1, zero, 0             # y = 0
                addi    t2, a2, 0               # z = theta
                addi    t3, zero, 0             # i = 0
                la      t4, atan_table          # t4 = &atan_table[0]

cordic_loop:
                addi    t5, zero, 16            # N = 16 iteraciones
                bge     t3, t5, cordic_end

                # Terminos desplazados: x >>> i  e  y >>> i 
                sra     t5, t0, t3              # t5 = x >>> i
                sra     t6, t1, t3              # t6 = y >>> i

                # Sentido de la rotacion segun el signo de z
                blt     t2, zero, cordic_neg    # z < 0  ->  d = -1

                # d = +1
                sub     t0, t0, t6              # x = x - (y >>> i)
                add     t1, t1, t5              # y = y + (x >>> i)
                lw      t5, 0(t4)               # t5 = alpha_i
                sub     t2, t2, t5              # z = z - alpha_i
                jal     zero, cordic_next

                # d = -1
cordic_neg:
                add     t0, t0, t6              # x = x + (y >>> i)
                sub     t1, t1, t5              # y = y - (x >>> i)
                lw      t5, 0(t4)               # t5 = alpha_i
                add     t2, t2, t5              # z = z + alpha_i

cordic_next:
                addi    t3, t3, 1               # i = i + 1
                addi    t4, t4, 4               # avanza a alpha_{i+1}
                jal     zero, cordic_loop

cordic_end:
                # Tras 16 iteraciones
                sw      t0, 0(a0)
                sw      t1, 0(a1)
                jalr    zero, ra, 0
