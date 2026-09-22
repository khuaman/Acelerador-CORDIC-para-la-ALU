//=============================================================================
// cordic.v -- Acelerador CORDIC iterativo (modo rotacion) para seno y coseno
//
// Calcula cos(theta) y sin(theta) usando unicamente sumas, restas y
// desplazamientos aritmeticos. Una iteracion por ciclo de reloj, controlada
// por una FSM IDLE -> INIT -> ITERATE -> DONE.
//
// ---------------------------------------------------------------------------
// REPRESENTACION DE PUNTO FIJO: Q2.30 con signo (complemento a dos)
// ---------------------------------------------------------------------------
//   Bits totales      : 32
//   Bits parte entera : 2  (1 de signo + 1 de magnitud entera)
//   Bits parte frac.  : 30
//   Rango representable : [-2.0 , +1.999999999]  = [-2^31, 2^31-1] / 2^30
//   Precision (LSB)     : 2^-30 = 9.3132e-10
//
//   Se eligio Q2.30 porque:
//     - |x| y |y| nunca superan 1.0 (el vector se normaliza con 1/K16),
//       asi que un solo bit entero da margen de sobra y evita desbordes.
//     - El angulo de entrada llega hasta pi/2 = 1.5708 rad, que tambien
//       cabe en el rango [-2, 2).
//     - Deja el maximo numero de bits para la parte fraccionaria, que es
//       donde vive toda la precision del resultado.
//
//   Precision efectiva: con N=16 iteraciones el angulo residual queda
//   acotado por atan(2^-15) = 3.0518e-05 rad, de modo que el error en
//   cos/sin es del orden de 2e-05 (~15 bits utiles), muy por encima del
//   LSB. El limite lo pone el numero de iteraciones, no el formato.
//
// ---------------------------------------------------------------------------
// CONVERGENCIA
// ---------------------------------------------------------------------------
//   El algoritmo converge para |theta| <= sum(atan(2^-i)) = 1.7433 rad
//   = 99.88 grados. Los angulos del enunciado (0 a 90) estan dentro del
//   rango, por lo que no hace falta pre-rotacion de cuadrante.
//
// ---------------------------------------------------------------------------
// GANANCIA
// ---------------------------------------------------------------------------
//   K16 = prod(sqrt(1 + 2^-2i), i=0..15) = 1.646760258
//   1/K16 = 0.607252935  ->  x0 = round(0.607252935 * 2^30) = 652032874
//   Al inicializar x0 = 1/K16 la ganancia acumulada se cancela sola y
//   despues de 16 iteraciones se obtiene x ~= cos(theta), y ~= sin(theta).
//=============================================================================

module cordic #(
  parameter WIDTH = 32,  // ancho de palabra
  parameter FRAC  = 30,  // bits fraccionarios (Q2.30)
  parameter ITER  = 16   // numero de iteraciones (fijado por el enunciado)
)(
  input  wire                    clk,
  input  wire                    reset,   // reset sincrono, activo en alto
  input  wire                    start,   // pulso de inicio
  input  wire signed [WIDTH-1:0] angle,   // theta en radianes, Q2.30
  output reg  signed [WIDTH-1:0] cos_out, // x ~= cos(theta), Q2.30
  output reg  signed [WIDTH-1:0] sin_out, // y ~= sin(theta), Q2.30
  output reg                     done     // 1 = resultado valido
);

  //---------------------------------------------------------------------------
  // Constante de compensacion de ganancia: x0 = 1/K16 en Q2.30
  //---------------------------------------------------------------------------
  localparam signed [WIDTH-1:0] INV_K = 32'd652032874; // 0.607252935

  //---------------------------------------------------------------------------
  // Codificacion de estados de la FSM
  //---------------------------------------------------------------------------
  localparam [1:0] S_IDLE    = 2'd0,  // espera start; conserva el resultado
                   S_INIT    = 2'd1,  // carga x0, y0, z0 y resetea el contador
                   S_ITERATE = 2'd2,  // una iteracion CORDIC por ciclo
                   S_DONE    = 2'd3;  // publica resultados y levanta done

  reg [1:0] state, next_state;

  //---------------------------------------------------------------------------
  // Registros internos del datapath
  //---------------------------------------------------------------------------
  reg signed [WIDTH-1:0] x_reg, y_reg, z_reg;
  reg        [4:0]       iter;  // contador de iteraciones (0..ITER-1)

  //---------------------------------------------------------------------------
  // Tabla de angulos: alpha_i = arctan(2^-i) en Q2.30
  //---------------------------------------------------------------------------
  reg [WIDTH-1:0] atan_lut [0:ITER-1];

  initial begin
    atan_lut[ 0] = 32'd843314857; // 0.785398163 rad = 45.000000 deg
    atan_lut[ 1] = 32'd497837829; // 0.463647609 rad = 26.565051 deg
    atan_lut[ 2] = 32'd263043837; // 0.244978663 rad = 14.036243 deg
    atan_lut[ 3] = 32'd133525159; // 0.124354995 rad =  7.125016 deg
    atan_lut[ 4] = 32'd67021687;  // 0.062418810 rad =  3.576334 deg
    atan_lut[ 5] = 32'd33543516;  // 0.031239833 rad =  1.789911 deg
    atan_lut[ 6] = 32'd16775851;  // 0.015623729 rad =  0.895174 deg
    atan_lut[ 7] = 32'd8388437;   // 0.007812341 rad =  0.447614 deg
    atan_lut[ 8] = 32'd4194283;   // 0.003906230 rad =  0.223811 deg
    atan_lut[ 9] = 32'd2097149;   // 0.001953123 rad =  0.111906 deg
    atan_lut[10] = 32'd1048576;   // 0.000976562 rad =  0.055953 deg
    atan_lut[11] = 32'd524288;    // 0.000488281 rad =  0.027976 deg
    atan_lut[12] = 32'd262144;    // 0.000244141 rad =  0.013988 deg
    atan_lut[13] = 32'd131072;    // 0.000122070 rad =  0.006994 deg
    atan_lut[14] = 32'd65536;     // 0.000061035 rad =  0.003497 deg
    atan_lut[15] = 32'd32768;     // 0.000030518 rad =  0.001749 deg
  end

  //---------------------------------------------------------------------------
  // Logica combinacional de una iteracion
  //
  //   d_i se deduce del signo de z_i: si z_i >= 0 rotamos en +1, si no en -1.
  //   El bit de signo de z_reg ya es esa decision, no hace falta comparador.
  //
  //     x_{i+1} = x_i - d_i*(y_i >>> i)
  //     y_{i+1} = y_i + d_i*(x_i >>> i)
  //     z_{i+1} = z_i - d_i*alpha_i
  //---------------------------------------------------------------------------
  wire d_neg = z_reg[WIDTH-1];  // 1 cuando z < 0, es decir d_i = -1

  wire signed [WIDTH-1:0] x_shifted = x_reg >>> iter;  // x_i * 2^-i
  wire signed [WIDTH-1:0] y_shifted = y_reg >>> iter;  // y_i * 2^-i
  wire signed [WIDTH-1:0] alpha     = $signed(atan_lut[iter]);

  wire signed [WIDTH-1:0] x_next = d_neg ? (x_reg + y_shifted) : (x_reg - y_shifted);
  wire signed [WIDTH-1:0] y_next = d_neg ? (y_reg - x_shifted) : (y_reg + x_shifted);
  wire signed [WIDTH-1:0] z_next = d_neg ? (z_reg + alpha)     : (z_reg - alpha);

  wire last_iter = (iter == ITER-1);

  //---------------------------------------------------------------------------
  // FSM: logica de proximo estado (combinacional)
  //---------------------------------------------------------------------------
  always @(*) begin
    case (state)
      S_IDLE:    next_state = start ? S_INIT : S_IDLE;
      S_INIT:    next_state = S_ITERATE;
      S_ITERATE: next_state = last_iter ? S_DONE : S_ITERATE;
      S_DONE:    next_state = start ? S_INIT : S_DONE;
      default:   next_state = S_IDLE;
    endcase
  end

  //---------------------------------------------------------------------------
  // FSM: registro de estado + datapath (secuencial)
  //---------------------------------------------------------------------------
  always @(posedge clk) begin
    if (reset) begin
      state   <= S_IDLE;
      x_reg   <= {WIDTH{1'b0}};
      y_reg   <= {WIDTH{1'b0}};
      z_reg   <= {WIDTH{1'b0}};
      iter    <= 5'd0;
      cos_out <= {WIDTH{1'b0}};
      sin_out <= {WIDTH{1'b0}};
      done    <= 1'b0;
    end else begin
      state <= next_state;

      case (state)
        //-- Espera. Los resultados de la operacion anterior siguen visibles
        //-- en cos_out/sin_out hasta que llegue un nuevo start.
        S_IDLE: begin
          if (start) done <= 1'b0;
        end

        //-- Carga del vector inicial: x0 = 1/K16, y0 = 0, z0 = theta.
        S_INIT: begin
          x_reg <= INV_K;
          y_reg <= {WIDTH{1'b0}};
          z_reg <= angle;
          iter  <= 5'd0;
          done  <= 1'b0;
        end

        //-- Una iteracion por ciclo. En la ultima se publican los resultados
        //-- para que ya esten listos al entrar en DONE.
        S_ITERATE: begin
          x_reg <= x_next;
          y_reg <= y_next;
          z_reg <= z_next;
          iter  <= iter + 5'd1;

          if (last_iter) begin
            cos_out <= x_next;
            sin_out <= y_next;
            done    <= 1'b1;
          end
        end

        //-- Resultado disponible. Se mantiene hasta un nuevo start.
        S_DONE: begin
          if (start) done <= 1'b0;
        end

        default: ; // nada
      endcase
    end
  end

endmodule
