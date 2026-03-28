`timescale 1ns/1ps
`default_nettype none

module core_fsm #(
    parameter bw        = 4,
    parameter psum_bw   = 16,
    parameter len_kij   = 9,
    parameter len_onij  = 16,
    parameter col       = 8,
    parameter row       = 8,
    parameter len_nij   = 36
)(
    input  wire                   clk,
    input  wire                   reset,
    input  wire                   start,

    // XMEM Port B (sys_clk domain, read-only)
    input  wire [bw*row-1:0]      xmem_doutb,   // 32 bits (8×4b)
    output wire  [10:0]            xmem_addrb_q,
    output wire                    xmem_enb,

    // RES Port A (sys_clk domain, write-only)
    output  reg [3:0] res_addra,
    output  reg        res_wea,     // write enable
    output  reg        res_ena,     // enable    

    // systolic core output
    output wire [col*psum_bw-1:0] core_out,

    // debug / status
    output logic [3:0]            debug_state,
    output wire                   done
);

    // =========================================================
    // Core control --> inst_q
    // =========================================================
    wire [34:0] inst_q;

    // Only PMEM + L0/ofifo control actually matter now.
    // XMEM CEN/WEN/A exist only for backward compatibility in 'inst_q'
    // but XMEM itself is outside in top_ok_core.
    reg                  CEN_xmem_q = 1, WEN_xmem_q = 1;
    reg [10:0]           A_xmem_q   = 0;
    reg                  CEN_pmem_q = 1, WEN_pmem_q = 1;
    reg [10:0]           A_pmem_q   = 0;
    reg [bw*row-1:0]     D_xmem_q   = 0;
    reg [7:0]            A_rom_q;
    reg                  ofifo_rd_q = 0;
    reg                  ififo_wr_q = 0, ififo_rd_q = 0;
    reg                  l0_rd_q    = 0, l0_wr_q    = 0;
    reg                  execute_q  = 0, load_q     = 0, acc_q = 0;
    reg [3:0]            res_addra_q; 
    reg                  res_wea_q, res_ena_q;
    reg                  mac_array_reset;

    assign inst_q[34]    = mac_array_reset;
    assign inst_q[33]    = acc_q;
    assign inst_q[32]    = CEN_pmem_q;
    assign inst_q[31]    = WEN_pmem_q;
    assign inst_q[30:20] = A_pmem_q;
    assign inst_q[19]    = CEN_xmem_q;
    assign inst_q[18]    = WEN_xmem_q;
    assign inst_q[17:7]  = A_xmem_q;
    assign inst_q[6]     = ofifo_rd_q;
    assign inst_q[5]     = ififo_wr_q;
    assign inst_q[4]     = ififo_rd_q;
    assign inst_q[3]     = l0_rd_q;
    assign inst_q[2]     = l0_wr_q;
    assign inst_q[1]     = execute_q;
    assign inst_q[0]     = load_q;

    assign xmem_addrb_q = A_xmem_q;
    assign xmem_enb = CEN_xmem_q;

    // =========================================================
    // Core instance
    // =========================================================

    core #(.bw(bw), .col(col), .row(row), .psum_bw(psum_bw)) core_instance (
        .clk        (clk),
        .reset      (reset),
        .inst       (inst_q),
        .D_xmem     (D_xmem_q),   // comes from XMEM Port B
        .ofifo_valid(),
        .sfu_out    (core_out)
    );

    rom rom (
        .clk(clk),
        .en(CEN_rom),
        .addr(A_rom),
        .dout(D_rom_q)
    );
    
    wire [10:0] D_rom_q;

    // =========================================================
    // FSM
    // =========================================================
    typedef enum logic [4:0] {
        IDLE,
        LOAD_KERNEL_L0,        // XMEM[W_BASE + kij*col ..] → L0
        LOAD_L0_PE,
        INTERMISSION,
        LOAD_ACT_L0,           // XMEM[0 .. len_nij-1] → L0
        EXECUTE,
        WRITEBACK_OFIFO_PMEM,
        ACC,
        DONE
    } State;

    State state, next_state;
    assign debug_state = state;
    assign done        = (state == DONE);

    reg [9:0] cnt;
    reg [9:0] outer_cnt_q;
    reg [9:0] inner_cnt_q;
    reg [3:0] kij;

    reg [9:0] outer_cnt;
    reg [9:0] inner_cnt;

    // timing params
    localparam int L0_LOAD_DELAY = 0;
    localparam int L0_EXEC_DELAY = 1;
    localparam int OFIFO_DELAY   = 1;

    // XMEM layout: host preloaded
    // [0 .. len_nij-1]          : activations
    // [W_BASE .. W_BASE+72-1]   : 9 kernels × 8 words each
    localparam int W_BASE        = 11'd1024;
    localparam int TOTAL_W_WORDS = len_kij * col;  // 9*8 = 72

    // combinational control
    // ChANGE TO WIRE ???
    reg                  CEN_xmem;
    reg                  WEN_xmem;
    reg [10:0]           A_xmem;
    reg                  CEN_pmem;
    reg                  WEN_pmem;
    reg [10:0]           A_pmem;
    reg [7:0]            A_rom;
    reg                  CEN_rom;
    reg                  ofifo_rd, ififo_wr, ififo_rd;
    reg                  l0_rd, l0_wr;
    reg                  execute, load, acc;

    // =========================================================
    // State / counters
    // =========================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            outer_cnt_q <= 0;
            inner_cnt_q <= 0;
            cnt   <= 0;
            kij   <= 0;
        end else begin
            state <= next_state;

            if (state != next_state)
                cnt <= 0;
            else
                cnt <= cnt + 1;

            if (state != ACC) begin
                outer_cnt_q <= 0;
                inner_cnt_q <= 0;
            end else begin
                outer_cnt_q <= outer_cnt;
                inner_cnt_q <= inner_cnt;
            end

            if (state == WRITEBACK_OFIFO_PMEM &&
                next_state == LOAD_KERNEL_L0)
                kij <= kij + 1;
            else if (state == IDLE && start)
                kij <= 0;
        end
    end

    // =========================================================
    // FSM combinational
    // =========================================================
    always @* begin
        next_state = state;

        CEN_xmem = 0;
        WEN_xmem = 0;
        A_xmem   = A_xmem_q;

        CEN_pmem = 0;
        WEN_pmem = 0;
        A_pmem   = A_pmem_q;

        CEN_rom  = 0;
        A_rom    = 0;

        ofifo_rd = 0;
        ififo_wr = 0;
        ififo_rd = 0;
        l0_rd    = 0;
        l0_wr    = 0;
        execute  = 0;
        load     = 0;
        acc      = 0;
        outer_cnt = outer_cnt_q; // hold by default
        inner_cnt = inner_cnt_q;

        res_addra = res_addra_q;
        res_wea = 0;
        res_ena = 0;

        mac_array_reset = 0;

        // XMEM Port B outputs

        case (state)

            // ------------------------------------------------
            IDLE: begin
                if (start)
                    next_state = LOAD_KERNEL_L0;
            end

            // ------------------------------------------------
            // Load one kernel (8 words) from XMEM → L0
            // kernel base = W_BASE + kij*col
            // ------------------------------------------------
            LOAD_KERNEL_L0: begin
                if (cnt == 0) begin
                    mac_array_reset = 1; // allow for later loading of mac_array
                    A_xmem = W_BASE + kij*col;
                end else if (cnt < col)
                    A_xmem = A_xmem_q + 1;

                if (cnt < col) begin
                    CEN_xmem  = 1;    // "enable" for inst_q bookkeeping
                end

                // account for 1-cycle XMEM latency: write to L0 starting at cnt>0
                if (cnt > 1 && cnt <= col+1)
                    l0_wr = 1;

                if (cnt == col+1)
                    next_state = LOAD_L0_PE;
            end

            // ------------------------------------------------
            LOAD_L0_PE: begin
                if (cnt < col)
                    l0_rd = 1;

                if (cnt >= L0_LOAD_DELAY)
                    load = 1;

                if (cnt == col + L0_LOAD_DELAY - 1)
                    next_state = INTERMISSION;
            end

            INTERMISSION: begin
                if (cnt == 15)
                    next_state = LOAD_ACT_L0;
            end

            // ------------------------------------------------
            // Load activations XMEM[0..len_nij-1] → L0
            // ------------------------------------------------
            LOAD_ACT_L0: begin
                if (cnt == 0)
                    A_xmem = 0;
                else if (cnt < len_nij)
                    A_xmem = A_xmem_q + 1;

                if (cnt < len_nij) begin
                    CEN_xmem = 1;
                end

                if (cnt > 1 && cnt <= len_nij+1)
                    l0_wr = 1;

                if (cnt == len_nij+1)
                    next_state = EXECUTE;
            end

            // ------------------------------------------------
            EXECUTE: begin
                if (cnt < len_nij)
                    l0_rd = 1;

                if (cnt >= L0_EXEC_DELAY)
                    execute = 1;

                if (cnt == len_nij + L0_EXEC_DELAY - 1)
                    next_state = WRITEBACK_OFIFO_PMEM;
            end

            // ------------------------------------------------
            // Write results kernel-by-kernel into PMEM
            // A_pmem base = kij * len_nij
            // ------------------------------------------------
            WRITEBACK_OFIFO_PMEM: begin
                if (cnt == 0)
                    A_pmem = kij * len_nij;
                else if (cnt < len_nij)
                    A_pmem = A_pmem_q + 1;

                if (cnt < len_nij) begin
                    CEN_pmem = 1;
                    WEN_pmem = 1;
                end

                if (cnt >= OFIFO_DELAY)
                    ofifo_rd = 1;

                if (cnt == len_nij + OFIFO_DELAY - 1) begin
                    if (kij == len_kij - 1)
                        next_state = ACC;
                    else
                        next_state = LOAD_KERNEL_L0;
                end
            end

            // ------------------------------------------------
            ACC: begin
                CEN_rom = 1;

                if (outer_cnt < len_onij) begin
                    if (inner_cnt == 0) begin
                        A_rom = len_kij * outer_cnt;
                    end else if (inner_cnt < len_kij) begin
                        A_rom = A_rom_q + 1;
                    end else begin
                        A_rom = A_rom_q;
                    end

                    if (inner_cnt > 0 && inner_cnt < len_kij+1) begin
                        CEN_pmem = 1;
                        WEN_pmem = 0;
                    end

                    if (inner_cnt > 1) begin
                        acc = 1;
                    end
                    
                    A_pmem = D_rom_q;
                end

                if (outer_cnt > 0) begin
                    // write from sfu to RES
                    if (inner_cnt == 1) begin
                        res_ena = 1;
                        res_wea = 1;

                        if (outer_cnt == 1) begin
                            res_addra = 0;
                        end else begin
                            res_addra = res_addra_q + 1;
                        end
                    end
                end
                
                if (inner_cnt == len_kij + 1) begin
                    outer_cnt = outer_cnt_q + 1;
                    inner_cnt = 0;
                end else begin
                    inner_cnt = inner_cnt_q + 1;
                end

                if (outer_cnt == len_onij+1) begin
                    next_state = DONE;
                end
            end

            // ------------------------------------------------
            DONE: begin
                next_state = IDLE;
            end

        endcase
    end

    // =========================================================
    // Register controls for the core
    // =========================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            CEN_xmem_q <= 1;
            WEN_xmem_q <= 1;
            A_xmem_q   <= 0;
            CEN_pmem_q <= 1;
            WEN_pmem_q <= 1;
            A_pmem_q   <= 0;
            D_xmem_q   <= {bw*row{1'b0}};
            A_rom_q    <= 0;
            ofifo_rd_q <= 0;
            ififo_wr_q <= 0;
            ififo_rd_q <= 0;
            l0_rd_q    <= 0;
            l0_wr_q    <= 0;
            execute_q  <= 0;
            load_q     <= 0;
            acc_q      <= 0;
            res_addra_q <= 0;
            res_wea_q  <= 0;
            res_ena_q  <= 0;
        end else begin
            CEN_xmem_q <= CEN_xmem;
            WEN_xmem_q <= WEN_xmem;
            A_xmem_q   <= A_xmem;
            CEN_pmem_q <= CEN_pmem;
            WEN_pmem_q <= WEN_pmem;
            A_pmem_q   <= A_pmem;
            A_rom_q    <= A_rom;

            // XMEM data comes straight from Port B
            D_xmem_q   <= xmem_doutb;

            ofifo_rd_q <= ofifo_rd;
            ififo_wr_q <= ififo_wr;
            ififo_rd_q <= ififo_rd;
            l0_rd_q    <= l0_rd;
            l0_wr_q    <= l0_wr;
            execute_q  <= execute;
            load_q     <= load;
            acc_q      <= acc;

            res_addra_q <= res_addra;
            res_wea_q  <= res_wea;
            res_ena_q  <= res_ena;
        end
    end

endmodule

