// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
// Modified to support both Weight Stationary (WS) and Output Stationary (OS) modes
module mac_row (clk, out_s, in_w, in_n, in_w_os, out_s_os, valid, inst_w, reset, mode_select, os_drain);

  parameter bw = 4;
  parameter psum_bw = 16;
  parameter col = 8;

  input  clk, reset;
  input  mode_select;                    // 0 = WS, 1 = OS
  input  os_drain;                       // OS mode: drain signal for this row
  output [psum_bw*col-1:0] out_s;
  output [col-1:0] valid;
  input  [bw-1:0] in_w;   
  input  [1:0] inst_w;     
  input  [psum_bw*col-1:0] in_n;  
  
  input  [bw*col-1:0] in_w_os;           // Weights from north (one per column)
  output [bw*col-1:0] out_s_os;          // Weights to south (one per column)

  wire  [(col+1)*bw-1:0] l_to_r;
  assign l_to_r[bw-1:0] = in_w;

  wire  [(col+1)*2-1:0] inst_l_to_r;
  assign inst_l_to_r[1:0] = inst_w;

  genvar i;
  generate
  for (i=1; i < col+1 ; i=i+1) begin : col_num
      mac_tile #(.bw(bw), .psum_bw(psum_bw)) mac_tile_instance (
        .clk(clk),
        .reset(reset),
        .mode_select(mode_select),
        .os_drain(os_drain),
        .in_w(l_to_r[bw*i-1:bw*(i-1)]),
        .out_e(l_to_r[bw*(i+1)-1:bw*i]),
        .inst_w(inst_l_to_r[2*i-1:2*(i-1)]),
        .inst_e(inst_l_to_r[2*(i+1)-1:2*i]),
        .in_n(in_n[psum_bw*i-1:psum_bw*(i-1)]),
        .out_s(out_s[psum_bw*i-1:psum_bw*(i-1)]),
        .in_w_os(in_w_os[bw*i-1:bw*(i-1)]),
        .out_s_os(out_s_os[bw*i-1:bw*(i-1)])
      );

     assign valid[i-1] = inst_l_to_r[2*(i+1)-1];
  end
  endgenerate

endmodule
