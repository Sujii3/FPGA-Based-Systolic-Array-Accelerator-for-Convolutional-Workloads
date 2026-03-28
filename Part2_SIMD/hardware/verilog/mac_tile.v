// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
module mac_tile (clk, out_s, in_w, out_e, in_n, inst_w, inst_e, reset, part2);

input part2;

parameter bw = 4;
parameter bw2 = bw/2;
parameter psum_bw = 16;

input  [psum_bw-1:0] in_n;
output [psum_bw-1:0] out_s;
input  [bw-1:0] in_w;
output [bw-1:0] out_e; 
input  [1:0] inst_w; // inst[1]:execute, inst[0]: kernel loading
output [1:0] inst_e;
input  clk;
input  reset;

reg    [1:0] inst_q;
reg    [bw-1:0] a_q;
reg    [bw-1:0] b_q_lsb;
reg    [bw-1:0] b_q_msb;
reg    [psum_bw-1:0] c_q;

reg    load_ready_q_lsb;
reg    load_ready_q_msb;


wire   [psum_bw-1:0] mac_out_lsb;
wire   [psum_bw-1:0] mac_out_msb;
wire   [psum_bw-1:0] mac_out;

wire [bw-1:0] a_q_lsb;
wire [bw-1:0] a_q_msb;

assign a_q_lsb = { {(bw-bw2){1'b0}}, a_q[bw2-1:0] };
assign a_q_msb = { {(bw-bw2){1'b0}}, a_q[bw-1:bw2] };

assign out_e = a_q;
assign inst_e = inst_q;
assign out_s = mac_out;

mac #(.bw(bw), .psum_bw(psum_bw)) mac_instance_lsb (
    .a(a_q_lsb), 
    .b(b_q_lsb),
    .c({psum_bw{1'b0}}),
	.out(mac_out_lsb)
);

mac #(.bw(bw), .psum_bw(psum_bw)) mac_instance_msb (
    .a(a_q_msb), 
    .b(b_q_msb),
    .c({psum_bw{1'b0}}),
	.out(mac_out_msb)
); 

assign mac_out = part2 ? (c_q + mac_out_msb + mac_out_lsb) :
                         (c_q + (mac_out_msb << bw2) + mac_out_lsb);

always @ (posedge clk) begin
    if (reset == 1'b1) begin
        inst_q <= 2'b0;
        load_ready_q_lsb <= 1'b1;
        load_ready_q_msb <= 1'b1;
        a_q <= {bw{1'b0}};
        b_q_lsb <= {bw{1'b0}};
        b_q_msb <= {bw{1'b0}};
        c_q <= {bw{1'b0}};
    end
    else begin
        inst_q[1] <= inst_w[1];
        c_q <= in_n;

        // activation loading
        if (inst_w[0] == 1'b1 || inst_w[1] == 1'b1) begin
            a_q <= in_w;
        end

        if (part2) begin // load two diff weights sequentially
            // load first weight
            if (inst_w[0] == 1'b1 && load_ready_q_msb == 1'b1) begin
                b_q_msb <= in_w;
                load_ready_q_msb <= 1'b0;
            end

            // load second weight
            if (inst_w[0] == 1'b1 && load_ready_q_msb == 1'b0 && load_ready_q_lsb == 1'b1) begin
                b_q_lsb <= in_w;
                load_ready_q_lsb <= 1'b0;
            end
        end
        else begin // part 1 load both weights at same time
            if (inst_w[0] == 1'b1 && load_ready_q_lsb == 1'b1) begin
                b_q_lsb <= in_w;
                b_q_msb <= in_w;
                load_ready_q_lsb <= 1'b0;
                load_ready_q_msb <= 1'b0;
            end
        end
        
        if (load_ready_q_msb == 1'b0 && load_ready_q_lsb == 1'b0) begin
            inst_q[0] <= inst_w[0];
        end
    end
end

endmodule
