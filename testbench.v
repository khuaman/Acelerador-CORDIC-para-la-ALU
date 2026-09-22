module testbench_ALU();

  // Stimulus registers
  reg [3:0] A;   // 4-bit input A
  reg [3:0] B;   // 4-bit input B
  reg [2:0] OP;  // 3-bit control

  // ALU output
  wire [3:0] Result;

  // Error counter for the self-checking tests
  integer errors = 0;

  // Instantiate the ALU module
  ALU_4bit ALU_inst (
    .A(A),
    .B(B),
    .OP(OP),
    .Result(Result)
  );

  // Apply one set of inputs and compare against the expected value
  task check;
    input [3:0] a;
    input [3:0] b;
    input [2:0] op;
    input [3:0] expected;
    begin
      A  = a;
      B  = b;
      OP = op;
      #10; // let the combinational logic settle before sampling
      $display("%4t\t%b\t%b\t%b\t%b\t%b\t%s",
               $time, A, B, OP, Result, expected,
               (Result === expected) ? "OK" : "FAIL");
      if (Result !== expected) errors = errors + 1;
    end
  endtask

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, testbench_ALU);

    $display("Time\tA\tB\tOP\tResult\tExpect\tStatus");
    $display("------------------------------------------------");

    // Test Case 1: Addition (2 + 5 = 7)
    check(4'b0010, 4'b0101, 3'b000, 4'b0111);
    // Addition with wrap-around (9 + 8 = 17 -> 1 in 4 bits)
    check(4'b1001, 4'b1000, 3'b000, 4'b0001);

    // Test Case 2: Subtraction (5 - 2 = 3)
    check(4'b0101, 4'b0010, 3'b001, 4'b0011);
    // Subtraction with borrow (2 - 5 = -3 -> 13 in 4 bits)
    check(4'b0010, 4'b0101, 3'b001, 4'b1101);

    // Test Case 3: AND
    check(4'b1100, 4'b1010, 3'b010, 4'b1000);

    // Test Case 4: OR
    check(4'b1100, 4'b1010, 3'b011, 4'b1110);

    // Test Case 5: XOR
    check(4'b1100, 4'b1010, 3'b100, 4'b0110);

    // Test Case 6: unused opcodes must default to zero
    check(4'b1111, 4'b1111, 3'b101, 4'b0000);
    check(4'b1111, 4'b1111, 3'b110, 4'b0000);
    check(4'b1111, 4'b1111, 3'b111, 4'b0000);

    $display("------------------------------------------------");
    if (errors == 0)
      $display("All tests passed.");
    else
      $display("%0d test(s) FAILED.", errors);

    $finish;
  end

endmodule
