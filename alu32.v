//=============================================================================
// alu32.v -- ALU de 32 bits con acelerador CORDIC integrado
//
// Extiende una ALU convencional con una operacion CORDIC multiciclo que
// calcula simultaneamente el seno y el coseno de un angulo.
//
// ---------------------------------------------------------------------------
// MODELO DE EJECUCION
// ---------------------------------------------------------------------------
// Las operaciones aritmetico-logicas son combinacionales: el resultado es
// valido en el mismo ciclo y done se mantiene en alto de forma permanente.
//
// La operacion CORDIC es multiciclo: se lanza con un pulso de start, mantiene
// busy en alto durante 18 ciclos y levanta done cuando el resultado esta
// listo. Mientras busy esta en alto la ALU ignora nuevos start.
//
// El angulo de entrada viaja por A (radianes en Q2.30). El coseno sale por
// Result y el seno por Result_hi, que para el resto de operaciones vale cero.
//
// ---------------------------------------------------------------------------
// FLAGS
// ---------------------------------------------------------------------------
// Zero, Negative      : derivados de Result, validos para toda operacion.
// Carry, Overflow     : solo tienen sentido en ADD y SUB; valen 0 en el resto.
//   - Carry en SUB sigue el convenio de RISC-V/ARM: 1 = NO hubo prestamo.
//   - Overflow es el desborde con signo (complemento a dos).
//=============================================================================

module alu32 #(
  parameter WIDTH = 32
)(
  input  wire                    clk,
  input  wire                    reset,     // reset sincrono, activo en alto
  input  wire                    start,     // pulso de inicio (solo CORDIC)
  input  wire signed [WIDTH-1:0] A,         // operando A / angulo para CORDIC
  input  wire signed [WIDTH-1:0] B,         // operando B
  input  wire        [3:0]       OP,        // selector de operacion
  output reg  signed [WIDTH-1:0] Result,    // resultado / coseno
  output wire signed [WIDTH-1:0] Result_hi, // seno (solo CORDIC), 0 en el resto
  output wire                    done,      // 1 = Result valido
  output wire                    busy,      // 1 = CORDIC en curso
  output wire                    Zero,
  output wire                    Negative,
  output reg                     Carry,
  output reg                     Overflow
);

  //---------------------------------------------------------------------------
  // Codificacion de operaciones
  //---------------------------------------------------------------------------
  localparam [3:0] OP_ADD    = 4'b0000,  // A + B
                   OP_SUB    = 4'b0001,  // A - B
                   OP_AND    = 4'b0010,  // A & B
                   OP_OR     = 4'b0011,  // A | B
                   OP_XOR    = 4'b0100,  // A ^ B
                   OP_SLL    = 4'b0101,  // A << B[4:0]
                   OP_SRL    = 4'b0110,  // A >> B[4:0]   (logico)
                   OP_SRA    = 4'b0111,  // A >>> B[4:0]  (aritmetico)
                   OP_SLT    = 4'b1000,  // (A < B) con signo -> 0 o 1
                   OP_CORDIC = 4'b1001;  // cos/sin de A, multiciclo

  wire is_cordic = (OP == OP_CORDIC);

  //---------------------------------------------------------------------------
  // Sumador/restador compartido, con un bit extra para capturar el acarreo
  //---------------------------------------------------------------------------
  wire [WIDTH:0] sum_ext  = {1'b0, A} + {1'b0, B};
  wire [WIDTH:0] diff_ext = {1'b0, A} - {1'b0, B};

  wire signed [WIDTH-1:0] sum  = sum_ext[WIDTH-1:0];
  wire signed [WIDTH-1:0] diff = diff_ext[WIDTH-1:0];

  // Desborde con signo: ocurre cuando los operandos "apuntan" al mismo lado
  // y el resultado cae al contrario.
  wire ovf_add = (~(A[WIDTH-1] ^ B[WIDTH-1])) & (A[WIDTH-1] ^ sum[WIDTH-1]);
  wire ovf_sub = ( (A[WIDTH-1] ^ B[WIDTH-1])) & (A[WIDTH-1] ^ diff[WIDTH-1]);

  //---------------------------------------------------------------------------
  // Instancia del acelerador CORDIC
  //
  // Solo arranca cuando la operacion seleccionada es CORDIC y no hay otra en
  // curso, de modo que un start espurio durante el calculo no lo reinicia.
  //---------------------------------------------------------------------------
  wire                    cordic_start = start & is_cordic & ~busy;
  wire signed [WIDTH-1:0] cordic_cos, cordic_sin;
  wire                    cordic_done;

  cordic #(
    .WIDTH (WIDTH),
    .FRAC  (30),
    .ITER  (16)
  ) cordic_inst (
    .clk     (clk),
    .reset   (reset),
    .start   (cordic_start),
    .angle   (A),
    .cos_out (cordic_cos),
    .sin_out (cordic_sin),
    .done    (cordic_done)
  );

  //---------------------------------------------------------------------------
  // Control de ocupacion: se levanta al lanzar el CORDIC y cae con su done
  //---------------------------------------------------------------------------
  reg busy_reg;

  always @(posedge clk) begin
    if (reset)
      busy_reg <= 1'b0;
    else if (cordic_start)
      busy_reg <= 1'b1;
    else if (cordic_done)
      busy_reg <= 1'b0;
  end

  // busy cae en el mismo ciclo en que el CORDIC termina, de modo que una
  // nueva operacion puede lanzarse sin perder un ciclo.
  assign busy = busy_reg & ~cordic_done;

  // Las operaciones combinacionales terminan en el acto; la CORDIC espera.
  assign done = is_cordic ? cordic_done : 1'b1;

  // El seno solo existe en la operacion CORDIC.
  assign Result_hi = is_cordic ? cordic_sin : {WIDTH{1'b0}};

  //---------------------------------------------------------------------------
  // Seleccion del resultado y de los flags aritmeticos
  //---------------------------------------------------------------------------
  always @(*) begin
    Carry    = 1'b0;
    Overflow = 1'b0;

    case (OP)
      OP_ADD: begin
        Result   = sum;
        Carry    = sum_ext[WIDTH];     // acarreo de salida
        Overflow = ovf_add;
      end

      OP_SUB: begin
        Result   = diff;
        Carry    = ~diff_ext[WIDTH];   // 1 = no hubo prestamo
        Overflow = ovf_sub;
      end

      OP_AND:    Result = A & B;
      OP_OR:     Result = A | B;
      OP_XOR:    Result = A ^ B;
      OP_SLL:    Result = A <<< B[4:0];
      OP_SRL:    Result = A >>  B[4:0];
      OP_SRA:    Result = A >>> B[4:0];
      OP_SLT:    Result = (A < B) ? {{(WIDTH-1){1'b0}}, 1'b1} : {WIDTH{1'b0}};
      OP_CORDIC: Result = cordic_cos;

      default:   Result = {WIDTH{1'b0}};
    endcase
  end

  //---------------------------------------------------------------------------
  // Flags derivados del resultado
  //---------------------------------------------------------------------------
  assign Zero     = (Result == {WIDTH{1'b0}});
  assign Negative = Result[WIDTH-1];

endmodule
