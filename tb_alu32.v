//=============================================================================
// tb_alu32.v -- Testbench de la ALU de 32 bits con acelerador CORDIC
//
// Cubre dos bloques:
//   1. Operaciones combinacionales: resultado y flags (Zero, Negative,
//      Carry, Overflow), incluyendo los casos limite de desborde con signo.
//   2. Operacion CORDIC multiciclo: protocolo start/busy/done y exactitud
//      del seno y el coseno frente a los valores ideales.
//=============================================================================

`timescale 1ns/1ps

module tb_alu32();

  localparam integer WIDTH  = 32;
  localparam real    SCALE  = 1073741824.0;  // 2^30
  localparam real    TOL    = 1.0e-04;
  localparam integer MAXCYC = 100;

  // Operaciones, replicadas aqui para que el testbench se lea solo
  localparam [3:0] OP_ADD    = 4'b0000, OP_SUB = 4'b0001, OP_AND = 4'b0010,
                   OP_OR     = 4'b0011, OP_XOR = 4'b0100, OP_SLL = 4'b0101,
                   OP_SRL    = 4'b0110, OP_SRA = 4'b0111, OP_SLT = 4'b1000,
                   OP_CORDIC = 4'b1001;

  reg                     clk = 1'b0;
  reg                     reset = 1'b1;
  reg                     start = 1'b0;
  reg  signed [WIDTH-1:0] A = {WIDTH{1'b0}};
  reg  signed [WIDTH-1:0] B = {WIDTH{1'b0}};
  reg         [3:0]       OP = OP_ADD;

  wire signed [WIDTH-1:0] Result, Result_hi;
  wire                    done, busy, Zero, Negative, Carry, Overflow;

  integer errors = 0;
  integer cycles = 0;

  alu32 dut (
    .clk (clk), .reset (reset), .start (start),
    .A (A), .B (B), .OP (OP),
    .Result (Result), .Result_hi (Result_hi),
    .done (done), .busy (busy),
    .Zero (Zero), .Negative (Negative),
    .Carry (Carry), .Overflow (Overflow)
  );

  always #5 clk = ~clk;

  function real q30_to_real;
    input signed [WIDTH-1:0] v;
    begin q30_to_real = $itor(v) / SCALE; end
  endfunction

  function real abs_real;
    input real v;
    begin abs_real = (v < 0.0) ? -v : v; end
  endfunction

  //---------------------------------------------------------------------------
  // Comprueba una operacion combinacional: resultado y los cuatro flags
  //---------------------------------------------------------------------------
  task check_op;
    input [95:0]             name;
    input [3:0]              op;
    input signed [WIDTH-1:0] a;
    input signed [WIDTH-1:0] b;
    input signed [WIDTH-1:0] exp_result;
    input                    exp_z;
    input                    exp_n;
    input                    exp_c;
    input                    exp_v;
    reg ok;
    begin
      A = a; B = b; OP = op;
      #1;  // deja asentar la logica combinacional
      ok = (Result === exp_result) && (Zero === exp_z) && (Negative === exp_n) &&
           (Carry === exp_c) && (Overflow === exp_v);

      $display("  %-12s A=0x%08X B=0x%08X -> R=0x%08X Z=%b N=%b C=%b V=%b   %0s",
               name, a, b, Result, Zero, Negative, Carry, Overflow,
               ok ? "OK" : "FAIL");

      if (!ok) begin
        $display("      esperado:                  R=0x%08X Z=%b N=%b C=%b V=%b",
                 exp_result, exp_z, exp_n, exp_c, exp_v);
        errors = errors + 1;
      end
    end
  endtask

  //---------------------------------------------------------------------------
  // Lanza la operacion CORDIC y verifica protocolo y exactitud
  //---------------------------------------------------------------------------
  task check_cordic;
    input [63:0]             name;
    input signed [WIDTH-1:0] theta_fx;
    input real               cos_exp;
    input real               sin_exp;
    real cos_got, sin_got, e_cos, e_sin;
    begin
      @(negedge clk);
      A = theta_fx; OP = OP_CORDIC; start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      if (!busy) begin
        $display("  FAIL: busy no se levanto al lanzar el CORDIC");
        errors = errors + 1;
      end

      cycles = 1;
      while (!done) begin
        @(negedge clk);
        cycles = cycles + 1;
        if (cycles > MAXCYC) begin
          $display("  FAIL: timeout esperando done");
          errors = errors + 1;
          $finish;
        end
      end

      if (busy) begin
        $display("  FAIL: busy sigue alto con done ya levantado");
        errors = errors + 1;
      end

      cos_got = q30_to_real(Result);
      sin_got = q30_to_real(Result_hi);
      e_cos   = abs_real(cos_got - cos_exp);
      e_sin   = abs_real(sin_got - sin_exp);

      $display("  %0s grados (%0d ciclos)  cos=%12.9f (err %.2e)  sin=%12.9f (err %.2e)  %0s",
               name, cycles, cos_got, e_cos, sin_got, e_sin,
               (e_cos <= TOL && e_sin <= TOL) ? "OK" : "FAIL");

      if (e_cos > TOL || e_sin > TOL) errors = errors + 1;
    end
  endtask

  //---------------------------------------------------------------------------
  initial begin
    $dumpfile("alu32.vcd");
    $dumpvars(0, tb_alu32);

    repeat (2) @(negedge clk);
    reset = 1'b0;
    @(negedge clk);

    $display("=====================================================================");
    $display(" ALU de 32 bits -- operaciones combinacionales");
    $display("=====================================================================");

    //-- Suma
    check_op("ADD",         OP_ADD, 32'sd10, 32'sd25, 32'sd35,  1'b0,1'b0,1'b0,1'b0);
    check_op("ADD cero",    OP_ADD, 32'sd5, -32'sd5,  32'sd0,   1'b1,1'b0,1'b1,1'b0);
    // 0x7FFFFFFF + 1: desborda el rango con signo pero no genera acarreo
    check_op("ADD ovf",     OP_ADD, 32'sh7FFFFFFF, 32'sd1, 32'sh80000000, 1'b0,1'b1,1'b0,1'b1);
    // 0xFFFFFFFF + 1: genera acarreo pero (-1)+1 = 0 no desborda con signo
    check_op("ADD carry",   OP_ADD, -32'sd1, 32'sd1, 32'sd0,   1'b1,1'b0,1'b1,1'b0);

    //-- Resta
    check_op("SUB",         OP_SUB, 32'sd25, 32'sd10, 32'sd15,  1'b0,1'b0,1'b1,1'b0);
    check_op("SUB neg",     OP_SUB, 32'sd10, 32'sd25, -32'sd15, 1'b0,1'b1,1'b0,1'b0);
    check_op("SUB cero",    OP_SUB, 32'sd7,  32'sd7,  32'sd0,   1'b1,1'b0,1'b1,1'b0);
    // 0x80000000 - 1: el minimo negativo desborda al restarle 1
    check_op("SUB ovf",     OP_SUB, 32'sh80000000, 32'sd1, 32'sh7FFFFFFF, 1'b0,1'b0,1'b1,1'b1);

    //-- Logicas: Carry y Overflow deben quedar en cero
    check_op("AND",         OP_AND, 32'hF0F0F0F0, 32'hFF00FF00, 32'hF000F000, 1'b0,1'b1,1'b0,1'b0);
    check_op("OR",          OP_OR,  32'hF0F0F0F0, 32'h0F0F0F0F, 32'hFFFFFFFF, 1'b0,1'b1,1'b0,1'b0);
    check_op("XOR",         OP_XOR, 32'hAAAAAAAA, 32'hFFFFFFFF, 32'h55555555, 1'b0,1'b0,1'b0,1'b0);
    check_op("XOR cero",    OP_XOR, 32'h12345678, 32'h12345678, 32'h00000000, 1'b1,1'b0,1'b0,1'b0);

    //-- Desplazamientos: los que necesita CORDIC en la version software
    check_op("SLL",         OP_SLL, 32'h00000001, 32'd4,  32'h00000010, 1'b0,1'b0,1'b0,1'b0);
    check_op("SRL",         OP_SRL, 32'h80000000, 32'd4,  32'h08000000, 1'b0,1'b0,1'b0,1'b0);
    // SRA replica el bit de signo: es el desplazamiento que usa el algoritmo
    check_op("SRA neg",     OP_SRA, 32'h80000000, 32'd4,  32'hF8000000, 1'b0,1'b1,1'b0,1'b0);
    check_op("SRA pos",     OP_SRA, 32'h40000000, 32'd4,  32'h04000000, 1'b0,1'b0,1'b0,1'b0);

    //-- Comparacion con signo
    check_op("SLT verdad",  OP_SLT, -32'sd5, 32'sd3,  32'sd1, 1'b0,1'b0,1'b0,1'b0);
    check_op("SLT falso",   OP_SLT, 32'sd3, -32'sd5,  32'sd0, 1'b1,1'b0,1'b0,1'b0);

    //-- Opcode no usado
    check_op("OP invalido", 4'b1111, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0, 1'b1,1'b0,1'b0,1'b0);

    $display("");
    $display("=====================================================================");
    $display(" Operacion CORDIC multiciclo");
    $display("=====================================================================");

    check_cordic("0",  32'd0,          1.000000000, 0.000000000);
    check_cordic("30", 32'd562209904,  0.866025404, 0.500000000);
    check_cordic("45", 32'd843314857,  0.707106781, 0.707106781);
    check_cordic("60", 32'd1124419809, 0.500000000, 0.866025404);
    check_cordic("90", 32'd1686629713, 0.000000000, 1.000000000);

    //-------------------------------------------------------------------------
    // Result_hi solo debe llevar el seno en la operacion CORDIC
    //-------------------------------------------------------------------------
    $display("");
    $display("--- Result_hi en operaciones no CORDIC ---");
    A = 32'sd10; B = 32'sd25; OP = OP_ADD;
    #1;
    if (Result_hi !== 32'd0) begin
      $display("  FAIL: Result_hi deberia ser 0 fuera de CORDIC (vale 0x%08X)", Result_hi);
      errors = errors + 1;
    end else if (done !== 1'b1) begin
      $display("  FAIL: done deberia estar alto para una operacion combinacional");
      errors = errors + 1;
    end else begin
      $display("  OK: Result_hi=0 y done alto de inmediato en ADD");
    end

    $display("");
    $display("=====================================================================");
    if (errors == 0)
      $display(" TODAS LAS PRUEBAS PASARON");
    else
      $display(" %0d COMPROBACION(ES) FALLARON", errors);
    $display("=====================================================================");
    $finish;
  end

endmodule
