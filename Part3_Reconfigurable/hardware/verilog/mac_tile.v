// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_tile (clk, out_s, in_w, out_e, in_n, in_w_os, out_s_os, inst_w, inst_e, reset, mode_select, os_drain);

parameter bw = 4;
parameter psum_bw = 16;

input  clk;
input  reset;
input  mode_select;          // 0 = Weight Stationary, 1 = Output Stationary
input  os_drain;             // OS mode: drain signal (1 cycle pulse per row)

// Data ports
input  [psum_bw-1:0] in_n;  
output [psum_bw-1:0] out_s; 
input  [bw-1:0] in_w; 
output [bw-1:0] out_e; 
input  [bw-1:0] in_w_os;     // Weight from north (OS mode)
output [bw-1:0] out_s_os;    // Weight to south (OS mode)

// Instruction ports
input  [1:0] inst_w;         // inst[1]:execute, inst[0]: load/reset
output [1:0] inst_e;         // Instruction to east


reg [bw-1:0] a_q;           
reg [bw-1:0] b_q;           
reg [psum_bw-1:0] c_q;      
reg [1:0] inst_q;        
reg load_ready_q;         

wire [psum_bw-1:0] mac_out;

mac #(.bw(bw), .psum_bw(psum_bw)) mac_instance (
    .a(a_q), 
    .b(b_q),
    .c(c_q),
    .out(mac_out)
); 


assign out_e = a_q;

assign inst_e = inst_q;

assign out_s_os = b_q;

// Output mux (simplified):
// - WS mode: output MAC result
// - OS mode + drain: output accumulated value 
// - OS mode + no drain: pass through from north
assign out_s = (mode_select == 1'b0) ? mac_out :  
               (os_drain) ? c_q :                 
               in_n;                

always @ (posedge clk) begin
    if (reset == 1'b1) begin
        inst_q <= 2'b0;
        load_ready_q <= 1'b1;
        a_q <= {bw{1'b0}};
        b_q <= {bw{1'b0}};
        c_q <= {psum_bw{1'b0}};
    end
    else begin
        inst_q[1] <= inst_w[1];

        if (mode_select == 1'b0) begin
            // ============ WEIGHT STATIONARY MODE ============
            c_q <= in_n;
            if (inst_w[0] == 1'b1 || inst_w[1] == 1'b1) begin
                a_q <= in_w;
            end

            if (inst_w[0] == 1'b1 && load_ready_q == 1'b1) begin
                b_q <= in_w;
                load_ready_q <= 1'b0;
            end

            if (load_ready_q == 1'b0) begin
                inst_q[0] <= inst_w[0];
            end
        end
        else begin
            // ============ OUTPUT STATIONARY MODE ============
            
            if (inst_w[1] == 1'b1) begin
                a_q <= in_w;
            end

            if (inst_w[1] == 1'b1) begin
                b_q <= in_w_os;
            end

            if (inst_w[0] == 1'b1) begin
                c_q <= {psum_bw{1'b0}};
            end
            else if (inst_w[1] == 1'b1) begin
                c_q <= mac_out;
            end

            inst_q[0] <= inst_w[0];
        end
    end
end

endmodule
