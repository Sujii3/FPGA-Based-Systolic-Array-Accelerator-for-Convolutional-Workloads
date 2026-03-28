module sram_xmem_32b_w2048_dp (
    // Port A : Host write (okClk)
    input  wire        clka,
    input  wire [31:0] dina,
    input  wire [10:0] addra,
    input  wire        wea,     // write enable
    input  wire        ena,     // enable

    // Port B : Core read/write (sys_clk)
    input  wire        clkb,
    input  wire [10:0] addrb,
    output reg  [31:0] doutb,
    input  wire        enb
);
    // 2048 words × 32 bits
    (* ram_style = "block" *) reg [31:0] mem [0:2047];

    // Port A (host write)
    always @(posedge clka) begin
        if (ena) begin
            if (wea)
                mem[addra] <= dina;
        end
    end

    // Port B (core read)
    always @(posedge clkb) begin
        if (enb)
            doutb <= mem[addrb];
    end

endmodule