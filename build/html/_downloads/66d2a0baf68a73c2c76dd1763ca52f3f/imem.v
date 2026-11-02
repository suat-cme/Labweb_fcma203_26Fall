//==========================================================================
// 模块名称 : imem
// 功能描述 : 指令存储器 —— 例化文件夹中已有 SUAT_sram（AW=14，16K x 32b）
//            只读使用：WREN 恒为 0，读出为组合逻辑（与单周期时序匹配：
//            当前 PC 在周期内直接送出指令，时钟沿才更新 PC/写状态）
//
//            纯可综合模块：不含 $readmemh 等系统函数，也不含 parameter。
//            仿真初始化（装入 imem.hex）由验证环境 tb_cpu_top_plan.sv
//            通过层次引用完成：$readmemh("imem.hex", dut.u_imem.u_sram.sram);
//==========================================================================
module imem (
    input  wire        clk,            // 时钟（sram 写口�?要，本模块只读，仅作连接�?
    input  wire [31:0] addr,           // 字节地址（来�? PC�?
    output wire [31:0] inst            // 取出�? 32 位指�?
);

    // 字节地址 -> 字地�?：取 addr[15:2]（sram 每个单元 32 位）
    sram #(.AW(14)) u_sram (
        .CLK   (clk),
        .ADDR  (addr[15:2]),
        .WDATA (32'b0),
        .WREN  (4'b0000),          // 只读：写使能恒为 0
        .RDATA (inst)
    );

endmodule
