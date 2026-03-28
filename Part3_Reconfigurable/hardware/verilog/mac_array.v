// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
// Modified to support both Weight Stationary (WS) and Output Stationary (OS) modes
module mac_array (clk, reset, out_s, in_w, in_n, in_w_os, inst_w, valid, mode_select, os_drain);

  parameter bw = 4;
  parameter psum_bw = 16;
  parameter col = 8;
  parameter row = 8;

  input  clk, reset;
  input  mode_select;                    // 0 = WS, 1 = OS
  input  os_drain;                       // OS mode: drain trigger (pulse for 1 cycle)
  output [psum_bw*col-1:0] out_s;
  input  [row*bw-1:0] in_w;           
  input  [1:0] inst_w;             
  input  [psum_bw*col-1:0] in_n;         // Partial sums from north (WS mode, usually 0)
  input  [bw*col-1:0] in_w_os;           // Weights from top (OS mode, one per column)
  output [col-1:0] valid;

  reg    [2*row-1:0] inst_w_temp;
  reg    [row-1:0] os_drain_pipeline;    // Cascading drain: Row 7 first, Row 0 last
  wire   [psum_bw*col*(row+1)-1:0] temp;           // Vertical psum connections
  wire   [bw*col*(row+1)-1:0] w_os_temp;           // Vertical weight connections for OS mode
  wire   [row*col-1:0] valid_temp;

  genvar i;
 
  assign out_s = temp[psum_bw*col*(row+1)-1:psum_bw*col*row];
  
  // Top row receives in_n (usually 0 for psum) and in_w_os (weights for OS)
  assign temp[psum_bw*col-1:0] = in_n;
  assign w_os_temp[bw*col-1:0] = in_w_os;
  
  // Valid signal: 
  // - WS mode: from bottom row during execute (valid_temp)
  // - OS mode: ONLY during drain (ignore valid_temp, use drain pipeline)
  assign valid = mode_select ? {col{|os_drain_pipeline}} : valid_temp[row*col-1:row*col-col];

  generate
  for (i=1; i < row+1 ; i=i+1) begin : row_num
      mac_row #(.bw(bw), .psum_bw(psum_bw), .col(col)) mac_row_instance (
        .clk(clk),
        .reset(reset),
        .mode_select(mode_select),
        .os_drain(os_drain_pipeline[i-1]),
        .in_w(in_w[bw*i-1:bw*(i-1)]),
        .inst_w(inst_w_temp[2*i-1:2*(i-1)]),
        .in_n(temp[psum_bw*col*i-1:psum_bw*col*(i-1)]),
        .valid(valid_temp[col*i-1:col*(i-1)]),
        .out_s(temp[psum_bw*col*(i+1)-1:psum_bw*col*i]),
        // OS mode connections - vertical weight flow
        .in_w_os(w_os_temp[bw*col*i-1:bw*col*(i-1)]),
        .out_s_os(w_os_temp[bw*col*(i+1)-1:bw*col*i])
      );
  end
  endgenerate

  always @ (posedge clk) begin
    // Instruction pipeline - delays instruction by 1 cycle per row (top to bottom)
    // Row 0 gets inst first, Row 7 gets it last
    inst_w_temp[1:0]   <= inst_w; 
    inst_w_temp[3:2]   <= inst_w_temp[1:0]; 
    inst_w_temp[5:4]   <= inst_w_temp[3:2]; 
    inst_w_temp[7:6]   <= inst_w_temp[5:4]; 
    inst_w_temp[9:8]   <= inst_w_temp[7:6]; 
    inst_w_temp[11:10] <= inst_w_temp[9:8]; 
    inst_w_temp[13:12] <= inst_w_temp[11:10]; 
    inst_w_temp[15:14] <= inst_w_temp[13:12]; 
    
    // Drain pipeline - REVERSE order: Row 7 (bottom) drains first, Row 0 (top) last
    // This allows values to cascade down through pass-through rows to OFIFO
    os_drain_pipeline[7] <= os_drain;            
    os_drain_pipeline[6] <= os_drain_pipeline[7];  
    os_drain_pipeline[5] <= os_drain_pipeline[6];  
    os_drain_pipeline[4] <= os_drain_pipeline[5];  
    os_drain_pipeline[3] <= os_drain_pipeline[4];  
    os_drain_pipeline[2] <= os_drain_pipeline[3];  
    os_drain_pipeline[1] <= os_drain_pipeline[2];  
    os_drain_pipeline[0] <= os_drain_pipeline[1]; 
  end

endmodule