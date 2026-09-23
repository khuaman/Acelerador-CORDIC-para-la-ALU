module cordic #(
  parameter WIDTH = 32,
  parameter FRAC  = 30,  // Q2.30
  parameter ITER  = 16   // numero de iteraciones
)(
  input  wire                    clk,
  input  wire                    reset,
  input  wire                    start,
  input  wire signed [WIDTH-1:0] angle, 
  output reg  signed [WIDTH-1:0] cos_out,
  output reg  signed [WIDTH-1:0] sin_out,
  output reg                     done 
);

  localparam signed [WIDTH-1:0] INV_K = 32'd652032874; // 0.607252935


  localparam [2:0] S_IDLE    = 3'd0, 
                   S_INIT    = 3'd1,
                   S_ROT_POS = 3'd2, 
                   S_ROT_NEG = 3'd3,
                   S_DONE    = 3'd4;

  reg [2:0] state, next_state;


  reg signed [WIDTH-1:0] x_reg, y_reg, z_reg;
  reg        [4:0]       iter;  // contador de iteraciones


  // Tabla de angulos
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

  wire signed [WIDTH-1:0] x_shifted = x_reg >>> iter;  // x_i * 2^-i
  wire signed [WIDTH-1:0] y_shifted = y_reg >>> iter;  // y_i * 2^-i
  wire signed [WIDTH-1:0] alpha     = $signed(atan_lut[iter]);

  // Valores siguientes para ROT_POS
  wire signed [WIDTH-1:0] x_next_pos = x_reg - y_shifted;
  wire signed [WIDTH-1:0] y_next_pos = y_reg + x_shifted;
  wire signed [WIDTH-1:0] z_next_pos = z_reg - alpha;

  // Valores siguientes para ROT_NEG
  wire signed [WIDTH-1:0] x_next_neg = x_reg + y_shifted;
  wire signed [WIDTH-1:0] y_next_neg = y_reg - x_shifted;
  wire signed [WIDTH-1:0] z_next_neg = z_reg + alpha;

  wire in_rot_pos = (state == S_ROT_POS);

  wire signed [WIDTH-1:0] x_next = in_rot_pos ? x_next_pos : x_next_neg;
  wire signed [WIDTH-1:0] y_next = in_rot_pos ? y_next_pos : y_next_neg;
  wire signed [WIDTH-1:0] z_next = in_rot_pos ? z_next_pos : z_next_neg;

  wire last_iter = (iter == ITER-1);

  always @(*) begin
    case (state)
      S_IDLE:    next_state = start ? S_INIT : S_IDLE;

      S_INIT:    next_state = angle[WIDTH-1] ? S_ROT_NEG : S_ROT_POS;

      S_ROT_POS: begin
        if (last_iter)
          next_state = S_DONE;
        else
          next_state = z_next[WIDTH-1] ? S_ROT_NEG : S_ROT_POS;
      end

      S_ROT_NEG: begin
        if (last_iter)
          next_state = S_DONE;
        else
          next_state = z_next[WIDTH-1] ? S_ROT_NEG : S_ROT_POS;
      end

      S_DONE:    next_state = start ? S_INIT : S_DONE;

      default:   next_state = S_IDLE;
    endcase
  end


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

        //-- Iteracion con d_i = +1 (angulo residual z >= 0):
        //-- Se resta angulo elemental para acercar z a cero.
        //--   x = x - (y >>> i)
        //--   y = y + (x >>> i)
        //--   z = z - alpha_i
        S_ROT_POS: begin
          x_reg <= x_next_pos;
          y_reg <= y_next_pos;
          z_reg <= z_next_pos;
          iter  <= iter + 5'd1;

          if (last_iter) begin
            cos_out <= x_next_pos;
            sin_out <= y_next_pos;
            done    <= 1'b1;
          end
        end

        //-- Iteracion con d_i = -1 (angulo residual z < 0):
        //-- Se suma angulo elemental para regresar z hacia cero.
        //--   x = x + (y >>> i)
        //--   y = y - (x >>> i)
        //--   z = z + alpha_i
        S_ROT_NEG: begin
          x_reg <= x_next_neg;
          y_reg <= y_next_neg;
          z_reg <= z_next_neg;
          iter  <= iter + 5'd1;

          if (last_iter) begin
            cos_out <= x_next_neg;
            sin_out <= y_next_neg;
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
