// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module sram_128b_w2048 (CLK, D, Q, CEN, WEN, A, A2, Q2);

  input  CLK;
  input  WEN;
  input  CEN;
  input  [127:0] D;
  input  [10:0] A;
  input  [10:0] A2;
  output [127:0] Q;
  output [127:0] Q2;
  parameter num = 2048;

  reg [127:0] memory [num-1:0];
  reg [10:0] add_q;
  reg [10:0] add_q2;
  assign Q = memory[add_q];
  assign Q2 = memory[add_q2];

  always @ (posedge CLK) begin

   if (!CEN && WEN) begin // read 
      add_q <= A;
      add_q2 <= A2;
   end
   if (!CEN && !WEN) // write
      memory[A] <= D; 

  end

endmodule
