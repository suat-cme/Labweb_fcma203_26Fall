//==========================================================================
// 模块名称 : dmem
// 功能描述 : 数据存储器 —— 例化文件夹中已有的 SUAT_sram（AW=14，16K x 32b）
//            WREN[3:0] 为字节写使能：写指令（sw）时接 4'b1111（全字写）
//            读出为组合逻辑，写为时钟上升沿完成
//
//            纯可综合模块：不含 $readmemh 等系统函数，也不含 parameter。
//            仿真初始化（装入 dmem.hex）由验证环境 tb_cpu_top_plan.sv
//            通过层次引用完成：$readmemh("dmem.hex", dut.u_dmem.u_sram.sram);
//==========================================================================
module dmem (
    input  wire        clk,            // 时钟
    input  wire [31:0] addr,           // 地址（来自 ALU result，字节地址）
    input  wire [31:0] wdata,          // 写数据（来自寄存器堆 Read data 2）
    input  wire        write_en,       // 写使能（来自主控制器 MemWrite）
    output wire [31:0] rdata           // 读数据（送 MemtoReg 多路选择器）
);

    // 字节地址 -> 字地址：取 addr[15:2]
    sram #(.AW(14)) u_sram (
        .CLK   (clk),
        .ADDR  (addr[15:2]),
        .WDATA (wdata),
        .WREN  ({4{write_en}}),    // sw 为全字写：4 个字节写使能同时有效
        .RDATA (rdata)
    );

endmodule
