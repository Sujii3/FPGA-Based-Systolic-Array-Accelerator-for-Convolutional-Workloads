`timescale 1ns/1ps
module top_ok_core_tb;

    // ============================================================
    // XMEM : dual-port BRAM
    //   Port A (okClk) : host writes activations & weights
    //   Port B (sys_clk): core_fsm reads
    // ============================================================
    localparam bw       = 4;
    localparam psum_bw  = 16;
    localparam len_kij  = 9;
    localparam len_onij = 16;
    localparam col      = 8;
    localparam row      = 8;
    localparam len_nij  = 36;

    localparam integer W_BASE = 11'd1024;

    reg clk;
    reg reset;
    reg start;

    wire [col*psum_bw-1:0] core_out;

    wire [3:0] res_addra;
    wire res_wea;
    wire res_ena;

    // XMEM Port B control (from FSM)
    wire [10:0] xmem_addrb;
    wire        xmem_enb;
    wire [31:0] xmem_doutb;


    reg [3:0] res_addrb;
    reg        res_enb;
    wire [127:0] res_doutb;

    // XMEM Port A (TB write)
    reg  [31:0] xmem_dina;
    reg  [10:0] xmem_addra;
    reg         any_we;

    sram_xmem_32b_w2048_dp xmem (
        // Port A : host write (okClk)
        .clka (clk),
        .dina (xmem_dina),
        .addra(xmem_addra),
        .wea  (any_we),   // write when either pipe writes
        .ena  (any_we),   // enable when we write

        // Port B : core read (sys_clk)
        .clkb (clk),
        .addrb(xmem_addrb),
        .doutb(xmem_doutb),
        .enb  (xmem_enb)
    );

    sram_128b_w16_dp res (
        // Port A : FSM write (sys_clk)
        .clka(clk),
        .dina(core_out),
        .addra(res_addra),
        .wea(res_wea),     // write enable
        .ena(res_ena),     // enable

        // Port B : okClk read/write
        .clkb(clk),
        .addrb(res_addrb),
        .doutb(res_doutb),
        .enb(res_enb)
    );

    // ============================================================
    // Core FSM + core array
    // ============================================================
    wire [3:0]             fsm_state;
    wire                   fsm_done;

    core_fsm #(
        .bw      (bw),
        .psum_bw (psum_bw),
        .len_kij (len_kij),
        .len_onij(len_onij),
        .col     (col),
        .row     (row),
        .len_nij (len_nij)
    ) fsm_inst (
        .clk        (clk),
        .reset      (reset),
        .start      (start),
    
        .xmem_doutb (xmem_doutb),
        .xmem_addrb_q (xmem_addrb),
        .xmem_enb   (xmem_enb),
    
        .core_out   (core_out),
        .debug_state(fsm_state),
        .done       (fsm_done),


        .res_addra(res_addra),
        .res_wea(res_wea),     // write enable
        .res_ena(res_ena)     // enable    
    );

    // ============================================================
    // TB bookkeeping
    // ============================================================
    integer x_file, x_scan_file;
    integer w_file, w_scan_file;
    integer out_file, out_scan_file;
    integer t, i, kij;
    integer error;

    reg [8*64-1:0] w_file_name;
    reg [8*64-1:0] captured_data;
    reg [127:0]    answer;

    initial begin
        $dumpfile("top_ok_core_tb.vcd");
        $dumpvars(0,top_ok_core_tb);
        //////// Reset /////////

        #2 clk = 1'b0;   reset = 1;
        #2 clk = 1'b1; 

        for (i=0; i<10 ; i=i+1) begin
            #2 clk = 1'b0;
            #2 clk = 1'b1;  
        end

        #2 clk = 1'b0;   reset = 0;
        #2 clk = 1'b1; 

        //////// WRITE IN ACTIVS ///////
        x_file = $fopen("activation.txt", "r");
        // Following three lines are to remove the first three comment lines of the file
        x_scan_file = $fscanf(x_file,"%s", captured_data);
        x_scan_file = $fscanf(x_file,"%s", captured_data);
        x_scan_file = $fscanf(x_file,"%s", captured_data);

        xmem_addra   = 0;

        for (t=0; t<len_nij; t=t+1) begin  
            #2 clk = 1'b0;  x_scan_file = $fscanf(x_file,"%32b", xmem_dina); any_we = 1; if (t>0) xmem_addra = xmem_addra + 1;
            #2 clk = 1'b1;   
        end

        #2 clk = 1'b0;    any_we = 0; xmem_addra = 0;
        #2 clk = 1'b1; 

        $fclose(x_file);
    
        //////// WRITE IN WEIGHTS ///////
        for (kij=0; kij<9; kij=kij+1) begin
            case(kij)
                0: w_file_name = "weight_k1.txt";
                1: w_file_name = "weight_k2.txt";
                2: w_file_name = "weight_k3.txt";
                3: w_file_name = "weight_k4.txt";
                4: w_file_name = "weight_k5.txt";
                5: w_file_name = "weight_k6.txt";
                6: w_file_name = "weight_k7.txt";
                7: w_file_name = "weight_k8.txt";
                8: w_file_name = "weight_k9.txt";
            endcase

            w_file = $fopen(w_file_name, "r");
            w_scan_file = $fscanf(w_file,"%s", captured_data);
            w_scan_file = $fscanf(w_file,"%s", captured_data);
            w_scan_file = $fscanf(w_file,"%s", captured_data);

            xmem_addra = W_BASE + kij * col;

            for (t=0; t<col; t=t+1) begin  
                #2 clk = 1'b0;  w_scan_file = $fscanf(w_file,"%32b", xmem_dina); any_we = 1; if (t>0) xmem_addra = xmem_addra + 1; 
                #2 clk = 1'b1;
            end

            #2 clk = 1'b0;  any_we = 0; xmem_addra = 0;
            #2 clk = 1'b1; 
        end

        // START compute

        #2 clk = 1'b0; start = 1;
        #2 clk = 1'b1;

        #2 clk = 1'b0; start = 0;
        #2 clk = 1'b1;

        while (~fsm_done) begin
            #2 clk = 1'b0;
            #2 clk = 1'b1;
        end

        // we have finished, read out RES to see if it matches
        out_file = $fopen("out.txt", "r");

        out_scan_file = $fscanf(out_file, "%s", captured_data);
        out_scan_file = $fscanf(out_file, "%s", captured_data);
        out_scan_file = $fscanf(out_file, "%s", captured_data);

        res_addrb = 0;
        res_enb = 1;
        #2 clk = 1'b0;
        #2 clk = 1'b1;
        error=0;
        for (i=0; i<len_onij; i=i+1) begin 
            #2 clk = 1'b0; 
            #2 clk = 1'b1; 
            out_scan_file = $fscanf(out_file,"%128b", answer);
            if (res_doutb == answer)
                $display("%2d-th output featuremap Data matched! :D", i); 
            else begin
                $display("%2d-th output featuremap Data ERROR!!", i); 
                $display("res_doutb: %128b", res_doutb);
                $display("answer: %128b", answer);
                error = 1;
            end

            if (i < len_onij) begin
                res_addrb = res_addrb + 1;
            end
        end

        if (error == 0) begin
            $display("############ No error detected ##############"); 
            $display("########### Project Completed !! ############"); 
        end
    end

endmodule
