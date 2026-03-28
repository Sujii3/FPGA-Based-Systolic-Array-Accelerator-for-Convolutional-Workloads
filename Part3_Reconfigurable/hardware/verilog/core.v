// xmem is left sram
// l0 is left ififo (activations)
// wfifo is top ififo (weights for OS mode)
// ofifo is bottom ofifo
// pmem is bottom sram

// Modified to support both Weight Stationary (WS) and Output Stationary (OS) modes
module core (clk, reset, inst, ofifo_valid, D_xmem, sfu_out);
    
    parameter bw = 4;
    parameter col = 8;
    parameter row = 8;
    parameter psum_bw = 16;

    input clk;
    input reset;
    input [37:0] inst;           // Extended to 38 bits for os_drain
    input [bw*row-1:0] D_xmem;
    output ofifo_valid;
    output [col*psum_bw-1:0] sfu_out;

    // Decoding from TB - extended instruction bus
    wire os_drain_q      = inst[37]; // OS mode: drain trigger
    wire mode_select_q   = inst[36]; // 0 = WS, 1 = OS
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

    // Internal connections
    wire [bw*row-1:0] xmem_to_l0; 
    wire [bw*row-1:0] l0_to_array;
    wire [bw*col-1:0] wfifo_to_array;  // Weight FIFO output to MAC array (OS mode)
    wire [psum_bw*col-1:0] array_to_ofifo;
    wire [psum_bw*col-1:0] ofifo_to_pmem; 
    wire [psum_bw*col-1:0] pmem_to_sfu; 
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

    // Debugging wires
    wire l0_full;
    wire l0_ready;
    wire wfifo_full;
    wire wfifo_ready;
    wire ofifo_full;
    wire ofifo_ready;
    wire [col-1:0] array_execute_valid;
     
    // L0 FIFO - Activation FIFO (used in both modes)
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

    // Weight FIFO - for OS mode vertical weight streaming
    // Reuses ififo module but configured for col (8 weights, one per column)
    // diagonal=1 to match activation skew (weights need same column delay as activations)
    // Reuses ififo_wr_q and ififo_rd_q signals for control
    ififo #(.bw(bw), .row(col), .diagonal(1)) wfifo_instance (
        .clk(clk),
        .reset(reset),
        .in(xmem_to_l0),           // Weights loaded from same XMEM
        .out(wfifo_to_array),
        .rd(ififo_rd_q),           // Reused: same as activation FIFO read in OS mode
        .wr(ififo_wr_q),           // Reused: same as activation FIFO write in OS mode
        .o_full(wfifo_full),
        .o_ready(wfifo_ready)
    );

    // MAC Array with mode select
    mac_array #(.bw(bw), .psum_bw(psum_bw), .row(row), .col(col)) mac_array_instance (
        .clk(clk),
        .reset(reset),
        .mode_select(mode_select_q),
        .os_drain(os_drain_q),
        .in_n({psum_bw*col{1'b0}}),  // 128 bits of zeros
        .out_s(array_to_ofifo),
        .in_w(l0_to_array),
        .in_w_os(wfifo_to_array),    // Weight input for OS mode
        .inst_w(inst_w),
        .valid(array_execute_valid)
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

    // SFU - accumulates partial sums in WS mode, pass-through with ReLU in OS mode
    sfu #(.col(col), .psum_bw(psum_bw)) sfu_instance (
        .clk(clk),
        .reset(reset),
        .acc(acc_q),
        .mode_select(mode_select_q),
        .in(pmem_to_sfu),
        .after_relu(sfu_out)
    );

    sram_128b_w2048 pmem_instance (
        .CLK(clk),
        .D(ofifo_to_pmem),
        .Q(pmem_to_sfu),
        .CEN(CEN_pmem_q),
        .WEN(WEN_pmem_q),
        .A(A_pmem_q)
    );

endmodule