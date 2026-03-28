`timescale 1ns/1ps

module top_ok_core(
    input  wire [4:0]  okUH,
    output wire [2:0]  okHU,
    inout  wire [31:0] okUHU,
    inout  wire        okAA,     

    input  wire sys_clkp,
    input  wire sys_clkn
);

    // ------------------------------------------------------------
    // Opal Kelly host interface
    // ------------------------------------------------------------
    wire        okClk;     // FrontPanel clock
    wire [112:0] okHE;     // host -> endpoints
    wire [64:0]  okEH;     // endpoints -> host

    okHost okHI (
        .okUH (okUH),
        .okHU (okHU),
        .okUHU(okUHU),
        .okAA (okAA),
        .okClk(okClk),
        .okHE (okHE),
        .okEH (okEH)
    );

    // Endpoint OR tree
    // 2 PipeIn + 5 WireOut = 7 endpoints on okEHx
    localparam integer N_EP = 8;
    wire [65*N_EP-1:0] okEHx;

    okWireOR #(.N(N_EP)) wireOR_inst (
        .okEH (okEH),
        .okEHx(okEHx)
    );

    // ------------------------------------------------------------
    // System clock from differential LVDS
    // ------------------------------------------------------------
    wire sys_clk_raw;
    // debug
    wire sys_clk = okClk;


    IBUFDS #(
        .DIFF_TERM("FALSE"),
        .IOSTANDARD("LVDS_25")
    ) sysclk_ibuf (
        .I (sys_clkp),
        .IB(sys_clkn),
        .O (sys_clk_raw)
    );

    BUFG sysclk_bufg (
        .I(sys_clk_raw),
        .O()
    );

    // ------------------------------------------------------------
    // Parameters (match TB / core_fsm)
    // ------------------------------------------------------------
    localparam bw       = 4;
    localparam psum_bw  = 16;
    localparam len_kij  = 9;
    localparam len_onij = 16;
    localparam col      = 8;
    localparam row      = 8;
    localparam len_nij  = 36;

    localparam integer W_BASE = 11'd1024;

    // ------------------------------------------------------------
    // WireIns
    // 0x00: control (reset/start)
    // 0x01: RES read address (host-controlled)
    // ------------------------------------------------------------
    wire [31:0] wi_control;
    wire [31:0] wi_res_addr;

    okWireIn ep00_control (
        .okHE      (okHE),
        .ep_addr   (8'h00),
        .ep_dataout(wi_control)
    );

    okWireIn ep01_resaddr (
        .okHE      (okHE),
        .ep_addr   (8'h01),
        .ep_dataout(wi_res_addr)
    );

    wire reset = wi_control[1];
    wire start = wi_control[0];

    // host visible RES address (B-port)
    reg [3:0] res_addrb;
    always @(posedge okClk) begin
        res_addrb <= wi_res_addr[3:0];
    end

    // ------------------------------------------------------------
    // PipeIns: activations (0x80) and weights (0x81)
    // ------------------------------------------------------------
    wire [31:0] x_pipe_data;
    wire [31:0] w_pipe_data;
    wire        x_pipe_write;
    wire        w_pipe_write;

    okPipeIn ep80_x (
        .okHE      (okHE),
        .okEH      (okEHx[1*65 +: 65]),
        .ep_addr   (8'h80),
        .ep_write  (x_pipe_write),
        .ep_dataout(x_pipe_data)
    );

    okPipeIn ep81_w (
        .okHE      (okHE),
        .okEH      (okEHx[2*65 +: 65]),
        .ep_addr   (8'h81),
        .ep_write  (w_pipe_write),
        .ep_dataout(w_pipe_data)
    );

    // ------------------------------------------------------------
    // XMEM : dual-port BRAM
    //   Port A (okClk) : host writes activations & weights
    //   Port B (sys_clk): core_fsm reads
    // ------------------------------------------------------------
    // Port A write address counters
    reg [10:0] act_wr_addr    = 11'd0;
    reg [10:0] weight_wr_addr = W_BASE[10:0];

    wire a_we   = x_pipe_write;
    wire w_we   = w_pipe_write;
    wire any_we = a_we | w_we;

    wire [31:0] xmem_dina  = a_we ? x_pipe_data  : w_pipe_data;
    wire [10:0] xmem_addra = a_we ? act_wr_addr : weight_wr_addr;

    // bump addresses when host writes
    always @(posedge okClk or posedge reset) begin
        if (reset) begin
            act_wr_addr    <= 11'd0;
            weight_wr_addr <= W_BASE[10:0];
        end else begin
            if (a_we)
                act_wr_addr <= act_wr_addr + 1'b1;
            if (w_we)
                weight_wr_addr <= weight_wr_addr + 1'b1;
        end
    end

    // XMEM Port B control (from FSM)
    wire [10:0] xmem_addrb;
    wire        xmem_enb;
    wire [31:0] xmem_doutb;

    sram_xmem_32b_w2048_dp xmem (
        // Port A : host write (okClk)
        .clka (okClk),
        .dina (xmem_dina),
        .addra(xmem_addra),
        .wea  (any_we),
        .ena  (any_we),

        // Port B : core read (sys_clk)
        .clkb (sys_clk),
        .addrb(xmem_addrb),
        .doutb(xmem_doutb),
        .enb  (xmem_enb)
    );

    // ------------------------------------------------------------
    // RES BRAM: core_fsm writes (sys_clk), host reads (okClk)
    // ------------------------------------------------------------
    wire [col*psum_bw-1:0] core_out;   // 128-bit
    wire [3:0]             res_addra;
    wire                   res_wea;
    wire                   res_ena;

    wire [127:0] res_doutb;
    wire         res_enb = 1'b1;       // always enabled for host reads

    sram_128b_w16_dp res_bram (
        // Port A : FSM write (sys_clk)
        .clka (sys_clk),
        .dina (core_out),
        .addra(res_addra),
        .wea  (res_wea),
        .ena  (res_ena),

        // Port B : host read (okClk)
        .clkb (okClk),
        .addrb(res_addrb),
        .doutb(res_doutb),
        .enb  (res_enb)
    );

    // ------------------------------------------------------------
    // Core FSM + systolic core
    // ------------------------------------------------------------
    wire [3:0] fsm_state;
    wire       fsm_done;

    core_fsm #(
        .bw      (bw),
        .psum_bw (psum_bw),
        .len_kij (len_kij),
        .len_onij(len_onij),
        .col     (col),
        .row     (row),
        .len_nij (len_nij)
    ) fsm_inst (
        .clk         (sys_clk),
        .reset       (reset),
        .start       (start),

        .xmem_doutb  (xmem_doutb[bw*row-1:0]), // 32 bits
        .xmem_addrb_q(xmem_addrb),
        .xmem_enb    (xmem_enb),

        // RES write port
        .res_addra   (res_addra),
        .res_wea     (res_wea),
        .res_ena     (res_ena),

        .core_out    (core_out),
        .debug_state (fsm_state),
        .done        (fsm_done)
    );

    // ------------------------------------------------------------
    // WireOuts
    //   0x20-0x23 : current RES word (128b -> 4×32b)
    //   0x30      : status (done + state)
    // ------------------------------------------------------------

    okWireOut ep20_res0 (
        .okHE    (okHE),
        .okEH    (okEHx[3*65 +: 65]),
        .ep_addr (8'h20),
        .ep_datain(res_doutb[31:0])
    );

    okWireOut ep21_res1 (
        .okHE    (okHE),
        .okEH    (okEHx[4*65 +: 65]),
        .ep_addr (8'h21),
        .ep_datain(res_doutb[63:32])
    );

    okWireOut ep22_res2 (
        .okHE    (okHE),
        .okEH    (okEHx[5*65 +: 65]),
        .ep_addr (8'h22),
        .ep_datain(res_doutb[95:64])
    );

    okWireOut ep23_res3 (
        .okHE    (okHE),
        .okEH    (okEHx[6*65 +: 65]),
        .ep_addr (8'h23),
        .ep_datain(res_doutb[127:96])
    );

    // status: [4:1] = state, [0] = done
    wire [31:0] status_word = {27'd0, fsm_state, fsm_done};

    okWireOut ep30_status (
        .okHE    (okHE),
        .okEH    (okEHx[7*65 +: 65]),
        .ep_addr (8'h30),
        .ep_datain(status_word)
    );

endmodule
