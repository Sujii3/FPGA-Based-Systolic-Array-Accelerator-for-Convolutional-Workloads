// xmem is left sram
// l0 is left ififo
// ififo is top ififo - for later weight stationary
// ofifo is bottom ofifo
// pmem is bottom sram

module core (clk, reset, inst, ofifo_valid, D_xmem, sfu_out, part2, sfu_out2);
    
    input part2;

    parameter bw = 4;
    parameter col = 8;
    parameter row = 8;
    parameter psum_bw = 16;

    input clk;
    input reset;
    input [44:0] inst;
    input [bw*row-1:0] D_xmem;
    output ofifo_valid;
    output [col*psum_bw-1:0] sfu_out;
    output [col*psum_bw-1:0] sfu_out2;

    // decoding from TB
    wire [10:0] A_pmem_q2 = inst[44:34];
    wire acc_q           = inst[33];
    wire CEN_pmem_q      = inst[32];
    wire WEN_pmem_q      = inst[31];
    wire [10:0] A_pmem_q = inst[30:20];
    wire CEN_xmem_q      = inst[19];
    wire WEN_xmem_q      = inst[18];
    wire [10:0] A_xmem_q = inst[17:7];
    wire ofifo_rd_q      = inst[6];
    wire ififo_wr_q      = inst[5];
    wire ififo_rd_q      = inst[4];
    wire l0_rd_q         = inst[3];
    wire l0_wr_q         = inst[2];
    wire execute_q       = inst[1];
    wire load_q          = inst[0];

    // internal connections
    wire [bw*row-1:0] xmem_to_l0; 
    wire [bw*row-1:0] l0_to_array;
    wire [psum_bw*col-1:0] array_to_ofifo;
    wire [psum_bw*col-1:0] ofifo_to_pmem; 
    wire [psum_bw*col-1:0] pmem_to_sfu; 
    wire [psum_bw*col-1:0] pmem_to_sfu2; 
    wire [1:0] inst_w = {execute_q, load_q}; // inst[1]:execute, inst[0]: kernel loading

    // D_xmem_q is 8*4 = 32
    sram_32b_w2048 xmem_instance (
        .CLK(clk),
        .D(D_xmem),
        .Q(xmem_to_l0),
        .CEN(CEN_xmem_q),
        .WEN(WEN_xmem_q),
        .A(A_xmem_q)
    );

    // debugging wires/unknown use
    wire l0_full; // When any of the rows if full and cannot accept a vector
    wire l0_ready; // Negation of full, can accept one full vector
    wire ififo_full;
    wire ififo_ready;
    wire ofifo_full;
    wire ofifo_ready;
    wire [7:0] array_execute_valid; // When each column has a value to write to PMEM
     
    ififo #(.bw(bw), .row(row)) l0_instance (
        .clk(clk),
        .reset(reset),
        .in(xmem_to_l0),
        .out(l0_to_array),
        .rd(l0_rd_q),
        .wr(l0_wr_q),
        .o_full(l0_full),
        .o_ready(l0_ready)
    );

    
    mac_array #(.bw(bw), .psum_bw(psum_bw), .row(row), .col(col)) mac_array_instance (
        .clk(clk),
        .reset(reset),
        .in_n(128'b0), // 128 bits
        .out_s(array_to_ofifo),
        .in_w(l0_to_array),
        .inst_w(inst_w),
        .valid(array_execute_valid),
        .part2(part2)
    );
    
    ofifo #(.bw(psum_bw), .col(col)) ofifo_instance (
        .clk(clk),
        .reset(reset),
        .in(array_to_ofifo),
        .out(ofifo_to_pmem),
        .rd(ofifo_rd_q),
        .wr(array_execute_valid),
        .o_full(ofifo_full),
        .o_ready(ofifo_ready),
        .o_valid(ofifo_valid)
    );

    // ovalid sent to control, ctrl sets ofifo rd and sram wr
    sfu #(.col(col), .psum_bw(psum_bw)) sfu_instance (
        .clk(clk),
        .reset(reset),
        .acc(acc_q),
        .in(pmem_to_sfu),
        .after_relu(sfu_out)
    );

    sfu #(.col(col), .psum_bw(psum_bw)) sfu_instance2 (
        .clk(clk),
        .reset(reset),
        .acc(acc_q),
        .in(pmem_to_sfu2),
        .after_relu(sfu_out2)
    );

    sram_128b_w2048 pmem_instance (
        .CLK(clk),
        .D(ofifo_to_pmem),
        .Q(pmem_to_sfu),
        .Q2(pmem_to_sfu2),
        .CEN(CEN_pmem_q),
        .WEN(WEN_pmem_q),
        .A(A_pmem_q),
        .A2(A_pmem_q2)
    );

    

endmodule