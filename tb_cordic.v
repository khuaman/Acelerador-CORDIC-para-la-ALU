`timescale 1ns/1ps

module tb_cordic();

  localparam integer WIDTH = 32;
  localparam real    SCALE = 1073741824.0;  // 2^30, factor de escala Q2.30
  localparam real    TOL   = 1.0e-04;       // margen de error admitido
  localparam integer MAXCYC = 100;

  reg                     clk = 1'b0;
  reg                     reset = 1'b1;
  reg                     start = 1'b0;
  reg  signed [WIDTH-1:0] angle = {WIDTH{1'b0}};
  wire signed [WIDTH-1:0] cos_out, sin_out;
  wire                    done;

  integer errors  = 0;
  integer cycles  = 0;
  integer latency = 0;

  cordic dut (
    .clk     (clk),
    .reset   (reset),
    .start   (start),
    .angle   (angle),
    .cos_out (cos_out),
    .sin_out (sin_out),
    .done    (done)
  );

  always #5 clk = ~clk;


  // Conversion Q2.30 con signo -> real, para poder imprimir en decimal

  function real q30_to_real;
    input signed [WIDTH-1:0] v;
    begin
      q30_to_real = $itor(v) / SCALE;
    end
  endfunction

  function real abs_real;
    input real v;
    begin
      abs_real = (v < 0.0) ? -v : v;
    end
  endfunction


  // Compara un resultado contra su valor ideal e imprime la fila del reporte

  task report_value;
    input [63:0]            label;     // "cos" o "sin"
    input signed [WIDTH-1:0] got_fx;   // valor obtenido en Q2.30
    input real               expected; // valor ideal
    real got, err_abs;
    begin
      got     = q30_to_real(got_fx);
      err_abs = abs_real(got - expected);

      if (abs_real(expected) > 1.0e-09)
        $display("   %0s  esperado=%12.9f  obtenido=%12.9f  err_abs=%.3e  err_rel=%.3e  %0s",
                 label, expected, got, err_abs, err_abs / abs_real(expected),
                 (err_abs <= TOL) ? "OK" : "FAIL");
      else
        // Error relativo indefinido cuando el valor esperado es cero
        $display("   %0s  esperado=%12.9f  obtenido=%12.9f  err_abs=%.3e  err_rel=     n/a  %0s",
                 label, expected, got, err_abs,
                 (err_abs <= TOL) ? "OK" : "FAIL");

      if (err_abs > TOL) errors = errors + 1;
    end
  endtask

  //---------------------------------------------------------------------------
  // Lanza una operacion, espera done y reporta ambos resultados
  //---------------------------------------------------------------------------
  task run_case;
    input [63:0]             name;      // angulo en grados, como texto
    input signed [WIDTH-1:0] theta_fx;  // angulo en Q2.30 (radianes)
    input real               cos_exp;
    input real               sin_exp;
    begin
      @(negedge clk);
      angle = theta_fx;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;

      // Cuenta ciclos hasta que el modulo levante done
      cycles = 1;
      while (!done) begin
        @(negedge clk);
        cycles = cycles + 1;
        if (cycles > MAXCYC) begin
          $display("ERROR: timeout esperando done en el caso %0s", name);
          errors = errors + 1;
          $finish;
        end
      end
      latency = cycles;

      $display("");
      $display("theta = %0s grados   (z0 = 0x%08X, %0d ciclos)", name, theta_fx, latency);
      report_value("cos", cos_out, cos_exp);
      report_value("sin", sin_out, sin_exp);
    end
  endtask

  //---------------------------------------------------------------------------
  // Secuencia de pruebas
  //---------------------------------------------------------------------------
  initial begin
    $dumpfile("cordic.vcd");
    $dumpvars(0, tb_cordic);

    $display("=====================================================================");
    $display(" Validacion CORDIC -- Q2.30, N=16 iteraciones, tolerancia %.1e", TOL);
    $display("=====================================================================");

    // Reset inicial
    repeat (2) @(negedge clk);
    reset = 1'b0;

    // Angulos de prueba

    run_case("0",  32'd0,          1.000000000, 0.000000000);
    run_case("30", 32'd562209904,  0.866025404, 0.500000000);
    run_case("45", 32'd843314857,  0.707106781, 0.707106781);
    run_case("60", 32'd1124419809, 0.500000000, 0.866025404);
    run_case("90", 32'd1686629713, 0.000000000, 1.000000000);

    // Angulos negativos
    run_case("-30", -32'sd562209904, 0.866025404, -0.500000000);
    run_case("-90", -32'sd1686629713, 0.000000000, -1.000000000);

    // El resultado debe seguir disponible mientras no se inicie otra operacion

    $display("");
    $display("--- Retencion del resultado tras DONE ---");
    repeat (20) @(negedge clk);
    if (done !== 1'b1) begin
      $display("   FAIL: done se cayo sin que llegara un nuevo start");
      errors = errors + 1;
    end else if (q30_to_real(sin_out) < -0.9999 - TOL || q30_to_real(sin_out) > -0.9999 + 0.001) begin
      $display("   FAIL: el resultado cambio tras DONE (sin=%.9f)", q30_to_real(sin_out));
      errors = errors + 1;
    end else begin
      $display("   OK: done sigue en alto y el resultado se mantiene tras 20 ciclos");
    end


    // El reset debe dejar el modulo limpio y listo para otra operacion

    $display("");
    $display("--- Reset y reutilizacion ---");
    @(negedge clk);
    reset = 1'b1;
    @(negedge clk);
    reset = 1'b0;
    if (done !== 1'b0) begin
      $display("   FAIL: done deberia estar en bajo despues del reset");
      errors = errors + 1;
    end else begin
      $display("   OK: done en bajo despues del reset");
    end
    run_case("45", 32'd843314857, 0.707106781, 0.707106781);

    //-------------------------------------------------------------------------
    $display("");
    $display("=====================================================================");
    if (errors == 0)
      $display(" TODAS LAS PRUEBAS PASARON  (latencia: %0d ciclos por operacion)", latency);
    else
      $display(" %0d COMPROBACION(ES) FALLARON", errors);
    $display("=====================================================================");
    $finish;
  end

endmodule
