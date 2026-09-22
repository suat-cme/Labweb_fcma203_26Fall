module seg_driver (
    clk     
    ,data   
    ,reset  
    ,code   
    ,cs_o   
);

input   wire            clk;    // 100 Mhz System Clock
input   wire   [31:0]   data;
input   wire            reset;
output  wire    [7:0]   code;
output  wire    [7:0]   cs_o;

reg [16:0]  cnt_1ms;
reg         flag_1ms;

always @(posedge clk or posedge reset) begin
    if (reset)
        cnt_1ms <= 17'd0;
    else if (cnt_1ms == 17'd99_999)
        cnt_1ms <= 17'd0;
    else
        cnt_1ms <= cnt_1ms + 1;
end

always @(posedge clk or posedge reset) begin
    if (reset)
        flag_1ms <= 1'b0;
    else if (cnt_1ms == 17'd99_999)
        flag_1ms <= 1'b1;
    else
        flag_1ms <= 1'b0;
end

reg     [7:0]   cs;
reg     [3:0]   value;

always @(posedge clk or posedge reset) begin
    if (reset)
        cs <= 8'h1;
    else if (flag_1ms)
        cs <= {cs[6:0], cs[7]};
end

always @(cs or data) begin
        case (cs)
            8'b00000001 : value = data[ 3: 0];
            8'b00000010 : value = data[ 7: 4];
            8'b00000100 : value = data[11: 8];
            8'b00001000 : value = data[15:12];
            8'b00010000 : value = data[19:16];
            8'b00100000 : value = data[23:20];
            8'b01000000 : value = data[27:24];
            8'b10000000 : value = data[31:28];
            default: value = 4'bxxxx;
        endcase
end

seg u_seg(value, 1'b0, cs, code, cs_o);

endmodule
