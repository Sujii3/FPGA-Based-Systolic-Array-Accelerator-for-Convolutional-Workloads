/**
* Assumption is accumulation is set high/low only at nededge
* Modified to support both Weight Stationary (WS) and Output Stationary (OS) modes:
* - WS Mode (mode_select=0): Accumulate partial sums, then apply ReLU
* - OS Mode (mode_select=1): Just apply ReLU (accumulation already done in PEs)
**/
module sfu (clk, reset, acc, in, after_relu, mode_select);

    parameter col = 8;
    parameter psum_bw = 16;

    input clk;
    input reset;
    input acc;
    input mode_select;  // 0 = WS (accumulate), 1 = OS (pass-through with ReLU)
    input [col*psum_bw-1:0] in;
    output [col*psum_bw - 1:0] after_relu;

    reg [col*psum_bw - 1:0] current_psum;
    reg acc_q;

    // ReLU: if MSB (sign bit) is 1, output 0; otherwise output the value
    genvar j;
    generate
        for (j = 0; j < col; j = j+1) begin
            assign after_relu[j * psum_bw +: psum_bw] = 
                current_psum[(j+1) * psum_bw - 1] == 1'b1 ?
                0 :
                current_psum[j * psum_bw +: psum_bw];
        end
    endgenerate

    integer i;
    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            current_psum <= 0;
            acc_q <= 0;
        end else begin
            acc_q <= acc;
            
            if (mode_select == 1'b0) begin
                // ============ WEIGHT STATIONARY MODE ============
                // Accumulate partial sums from PMEM
                if (~acc_q & acc) begin 
                    // First cycle of accumulation: load the input
                    current_psum <= in;
                end else if (acc) begin 
                    // Subsequent cycles: accumulate
                    for (i = 0; i < col; i = i + 1) begin
                        current_psum[i * psum_bw +: psum_bw] <= current_psum[i * psum_bw +: psum_bw] + in[i * psum_bw +: psum_bw];
                    end
                end
            end else begin
                // ============ OUTPUT STATIONARY MODE ============
                // No accumulation
                // Just pass through the input (ReLU applied via assign)
                if (acc) begin
                    current_psum <= in;
                end
            end
        end
    end

endmodule
