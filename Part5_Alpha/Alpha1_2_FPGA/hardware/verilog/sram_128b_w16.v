// superpingu
module sram_128b_w16_dp (
    // Port A : FSM write (sys_clk)
    input  wire        clka,
    input  wire [127:0] dina,
    input  wire [3:0] addra,
    input  wire        wea,     // write enable
    input  wire        ena,     // enable

    // Port B : okClk read/write
    input  wire        clkb,
    input  wire [3:0] addrb,
    output reg  [127:0] doutb,
    input  wire        enb
);
    // 2048 words × 32 bits
    (* ram_style = "block" *) reg [127:0] mem [0:15];

    // Port A (FSM write)
    always @(posedge clka) begin
        if (ena) begin
            if (wea)
                mem[addra] <= dina;
        end
    end

    // Port B (host read)
    always @(posedge clkb) begin
        if (enb)
            doutb <= mem[addrb];
    end

endmodule
