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

  wire [WIDTH:0] sum_ext  = {1'b0, A} + {1'b0, B};
  wire [WIDTH:0] diff_ext = {1'b0, A} - {1'b0, B};

  wire signed [WIDTH-1:0] sum  = sum_ext[WIDTH-1:0];
  wire signed [WIDTH-1:0] diff = diff_ext[WIDTH-1:0];

  // Desborde con signo
  wire ovf_add = (~(A[WIDTH-1] ^ B[WIDTH-1])) & (A[WIDTH-1] ^ sum[WIDTH-1]);
  wire ovf_sub = ( (A[WIDTH-1] ^ B[WIDTH-1])) & (A[WIDTH-1] ^ diff[WIDTH-1]);


  // Instancia del acelerador CORDIC

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


  reg busy_reg;

  always @(posedge clk) begin
    if (reset)
      busy_reg <= 1'b0;
    else if (cordic_start)
      busy_reg <= 1'b1;
    else if (cordic_done)
      busy_reg <= 1'b0;
  end

  
  assign busy = busy_reg & ~cordic_done;

  
  assign done = is_cordic ? cordic_done : 1'b1;

  
  assign Result_hi = is_cordic ? cordic_sin : {WIDTH{1'b0}};


  // Seleccion del resultado

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
        Carry    = ~diff_ext[WIDTH];  
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


  // Flags derivados del resultado
  
  assign Zero     = (Result == {WIDTH{1'b0}});
  assign Negative = Result[WIDTH-1];

endmodule
