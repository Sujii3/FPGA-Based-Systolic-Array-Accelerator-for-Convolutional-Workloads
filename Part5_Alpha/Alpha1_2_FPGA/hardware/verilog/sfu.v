    /*
    reg [psum_bw - 1:0] after_relu_q [col - 1:0];
    reg [psum_bw - 1:0] current_psum [col - 1:0];
    */

/**
* Assumption is accumulation is set high/low only at nededge
**/
module sfu (clk, reset, acc, in, after_relu);

    parameter col = 8;
    parameter psum_bw = 16;

    input clk;
    input reset;
    input acc;
    input [col*psum_bw-1:0] in;
    output [col*psum_bw - 1:0] after_relu;

    reg [col*psum_bw - 1:0] current_psum;
    reg acc_q;

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
            
            if (~acc_q & acc) begin 
                // this is the first cycle of accumulator, take in the current input
                current_psum <= in;
            end else if (acc) begin 
                // addition phase of accumulator
                for (i = 0; i < col; i = i + 1) begin
                    current_psum[i * psum_bw +: psum_bw] <= current_psum[i * psum_bw +: psum_bw] + in[i * psum_bw +: psum_bw];
                end
            end
        end
    end

endmodule
