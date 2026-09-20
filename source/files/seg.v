/*
    code[0] -> DP       cs_o[0] -> A[0]
    code[1] -> CG       cs_o[1] -> A[1]
    code[2] -> CF       cs_o[2] -> A[2]
    code[3] -> CE       cs_o[3] -> A[3]
    code[4] -> CD       cs_o[4] -> A[4]
    code[5] -> CC       cs_o[5] -> A[5]
    code[6] -> CB       cs_o[6] -> A[6]
    code[7] -> CA       cs_o[7] -> A[7]
*/

module seg (value, point, cs_i, code, cs_o);

input   wire    [3:0]   value;
input   wire            point;
input   wire    [7:0]   cs_i;
output  wire    [7:0]   code;
output  wire    [7:0]   cs_o;

reg [6:0] segs;   // Active Low
always @(value) begin
    case (value)
        4'h0 : segs = 7'b0000001;
        4'h1 : segs = 7'b1001111;
        4'h2 : segs = 7'b0010010;
        4'h3 : segs = 7'b0000110;
        4'h4 : segs = 7'b1001100;
        4'h5 : segs = 7'b0100100;
        4'h6 : segs = 7'b0100000;
        4'h7 : segs = 7'b0001111;
        4'h8 : segs = 7'b0000000;
        4'h9 : segs = 7'b0000100;
        4'ha : segs = 7'b0001000;
        4'hb : segs = 7'b1100000;
        4'hc : segs = 7'b0110001;
        4'hd : segs = 7'b1000010;
        4'he : segs = 7'b0110000;
        4'hf : segs = 7'b0111000;
        // no default case
    endcase
end

wire point_en;  // Active Low
assign point_en = ~point;
assign code = {segs, point_en};
assign cs_o = ~cs_i;    // Active Low

endmodule
