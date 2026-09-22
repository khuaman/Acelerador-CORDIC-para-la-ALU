# Simulacion con Icarus Verilog.
#   make cordic  -> validacion del acelerador CORDIC (seccion 5 del enunciado)
#   make alu     -> ALU de 32 bits: operaciones, flags y operacion CORDIC
#   make all     -> ambas
#   make clean   -> borra binarios y volcados de onda

IVERILOG = iverilog -g2005
VVP      = vvp

.PHONY: all cordic alu clean

all: cordic alu

cordic: cordic_tb.out
	$(VVP) cordic_tb.out

alu: alu32_tb.out
	$(VVP) alu32_tb.out

cordic_tb.out: cordic.v tb_cordic.v
	$(IVERILOG) -o $@ cordic.v tb_cordic.v

alu32_tb.out: alu32.v cordic.v tb_alu32.v
	$(IVERILOG) -o $@ alu32.v cordic.v tb_alu32.v

clean:
	rm -f *.out *.vcd
