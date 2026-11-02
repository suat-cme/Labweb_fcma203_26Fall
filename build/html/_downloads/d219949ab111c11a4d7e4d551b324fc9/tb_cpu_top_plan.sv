//==========================================================================
// 模块名称 : tb_cpu_top_plan
// 功能描述 : 七指令单周期处理器验证环境（SystemVerilog，Vivado xsim 可直接运行）
//
// 验证方法：
//   测试平台内部实现一个"黄金参考模型"（ISA 级指令模拟器，仅含 7 条指令），
//   在每个时钟下降沿（DUT 时序状态已稳定）对以下状态做逐周期比对：
//     1) PC            : dut.pc        vs 黄金模型 g_pc
//     2) 32 位指令编码 : dut.inst      vs 指令存储器在黄金 PC 处的字
//     3) 32 个寄存器   : dut.u_regfile.regs[0..31] vs g_regs[0..31]
//     4) 数据存储器    : 黄金模型写过的字逐周期比对；
//                        仿真结束时对 16K 全空间做一次性最终比对
//
//   比对顺序：先 golden_step() 执行当前指令，再与 DUT 比对
//             （DUT 在上个时钟上升沿已执行同一指令，二者严格同拍）
//
// 错误诊断：首个不匹配时打印出错现场 —
//     出错指令的 PC、DUT 与黄金模型各自的 PC、指令二进制编码、反汇编汇编文本、
//     源操作数（寄存器双方值 / 符号扩展立即数双方值）、
//     出错寄存器编号及双方值、出错数据内存字节地址及双方值。
//
// 激励来源：
//   imem.hex / dmem.hex 由 gen_tests.py 生成（定向边界测试或随机测试）。
//   DUT 与黄金模型的存储器映像都由本环境在时间 0 用 $readmemh 装入
//   （imem/dmem 模块为纯可综合设计，不含系统函数）：
//     $readmemh("imem.hex", dut.u_imem.u_sram.sram);
//     $readmemh("dmem.hex", dut.u_dmem.u_sram.sram);
//   注意：必须把这两个 hex 文件加入 Simulation Sources（作为数据文件），
//   Vivado 才会在每次仿真启动时把它们复制到 xsim 运行目录，
//   使 $readmemh 的相对路径能够找到（否则存储器全 X，比对必然失败）。
//
// Vivado 使用步骤：
//   1. 将全部设计 .v 与本文件加入 Simulation Sources，top = tb_cpu_top_plan
//   2. 把 imem.hex、dmem.hex 一并加入 Simulation Sources（类型自动识别为
//      Data Files）；建议导入时不勾选 "Copy sources into project"，
//      直接引用工作目录中的文件，重新生成 hex 后无需再导入
//   3. 工程中的设计源文件修改后，需同步更新工程内的副本（重新导入），
//      否则端口改动（如 start_pc）会导致 X 传播
//   4. 每次重新生成 imem.hex / dmem.hex 后，重新 Run Simulation
//   5. 可选：-testplusarg verbose 打印取指轨迹；
//      -generic_top "MAX_CYCLES=1000" 调整比对周期数；
//      -generic_top "START_PC=32'h00000000" 更换程序起始地址
//==========================================================================
`timescale 1ns/1ps

module tb_cpu_top_plan;

    parameter integer MAX_CYCLES = 50;   // 比对周期数（每条指令 1 周期）
    // 程序起始地址：必须与 gen_tests.py 的 --start-pc 一致（默认 0x100）
    parameter logic [31:0] START_PC = 32'h0000_0100;

    logic clk = 1'b0;
    logic reset;
    always #5 clk = ~clk;                  // 100MHz

    // 待测处理器
    cpu_top dut (
        .clk      (clk),
        .reset    (reset),
        .start_pc (START_PC)
    );

    //--------------------------------------------------------------------------
    // 黄金参考模型状态
    //--------------------------------------------------------------------------
    logic [31:0] g_imem [0:16383];         // 指令映像（与 DUT 读同一份 imem.hex）
    logic [31:0] g_dmem [0:16383];         // 数据映像（与 DUT 读同一份 dmem.hex）
    logic [31:0] g_regs [0:31];            // 32 个寄存器
    logic [31:0] g_pc;                     // 程序计数器
    logic        touched [0:16383];        // g_dmem 写过的字（逐周期比对这些字）

    logic [31:0] cur_instr_pc;             // 本周期执行的指令的 PC（出错现场用）
    bit          ctx_printed;              // 本周期是否已打印出错现场头

    // 本周期指令的源操作数（执行周期内采样，出错现场打印用）
    logic [31:0] cur_dut_op1, cur_dut_op2; // DUT 寄存器读口 1/2（执行周期内的值）
    logic [31:0] cur_dut_imm;              // DUT imm_gen 输出的符号扩展立即数
    logic [31:0] cur_g_op1,  cur_g_op2;    // 黄金模型读出的寄存器操作数快照
    logic [31:0] cur_g_imm;                // 黄金模型的符号扩展立即数

    longint unsigned cycle_cnt = 0;        // 已比对周期数
    integer cmp_cnt  = 0;                  // 比对项总数
    integer error_cnt = 0;                 // 错误总数
    bit verbose;                           // verbose 开关（+verbose 打印轨迹）

    initial begin
        for (int i = 0; i < 16384; i++) touched[i] = 1'b0;
        // 黄金参考模型映像
        $readmemh("imem.hex", g_imem);
        $readmemh("dmem.hex", g_dmem);
        // DUT 存储器映像（imem/dmem 为纯可综合模块，装入由本环境完成）
        $readmemh("imem.hex", dut.u_imem.u_sram.sram);
        $readmemh("dmem.hex", dut.u_dmem.u_sram.sram);
        verbose = $test$plusargs("verbose");

        // ---------- hex 装载自检 ----------
        // 若首条指令或 dmem 字 0 仍为 X，说明 hex 文件没找到：
        // 请把 imem.hex / dmem.hex 加入 Simulation Sources（数据文件）
        if ((^g_imem[START_PC[15:2]]) === 1'bx || (^g_dmem[0]) === 1'bx) begin
            $display("FATAL: imem.hex / dmem.hex not loaded (file path issue).");
            $display("       Add both hex files to Simulation Sources, then re-run.");
            $fatal(1, "hex files not loaded");
        end
    end

    //--------------------------------------------------------------------------
    // 执行周期内采样 DUT 的源操作数
    // （posedge 时刻 PC/指令/寄存器读口仍为旧值，NBA 更新尚未发生，
    //   因此采到的正是本周期指令实际使用的操作数）
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!reset) begin
            cur_dut_op1 <= dut.read_data_1;   // 寄存器读口 1（rs1 的值）
            cur_dut_op2 <= dut.read_data_2;   // 寄存器读口 2（rs2 / sw 的存储数据）
            cur_dut_imm <= dut.imm;           // imm_gen 符号扩展立即数
        end
    end

    //--------------------------------------------------------------------------
    // 符号扩展辅助函数
    //--------------------------------------------------------------------------
    function automatic logic [31:0] sext12(input logic [11:0] x);
        return {{20{x[11]}}, x};
    endfunction
    function automatic logic [31:0] sext13(input logic [12:0] x);
        return {{19{x[12]}}, x};
    endfunction

    //--------------------------------------------------------------------------
    // 反汇编器：32 位指令编码 -> 汇编文本（仅 7 条目标指令）
    //--------------------------------------------------------------------------
    function automatic string disasm(input logic [31:0] instr);
        logic [6:0] op;
        logic [4:0] rd, rs1, rs2;
        logic [2:0] f3;
        logic [6:0] f7;
        logic signed [11:0] imm12;
        logic signed [12:0] imm13;
        begin
            op  = instr[6:0];
            rd  = instr[11:7];
            f3  = instr[14:12];
            rs1 = instr[19:15];
            rs2 = instr[24:20];
            f7  = instr[31:25];
            case (op)
                7'b0110011: begin                     // R 型
                    case ({f7, f3})
                        {7'h00, 3'b000}: return $sformatf("add  x%0d, x%0d, x%0d", rd, rs1, rs2);
                        {7'h20, 3'b000}: return $sformatf("sub  x%0d, x%0d, x%0d", rd, rs1, rs2);
                        {7'h00, 3'b111}: return $sformatf("and  x%0d, x%0d, x%0d", rd, rs1, rs2);
                        {7'h00, 3'b110}: return $sformatf("or   x%0d, x%0d, x%0d", rd, rs1, rs2);
                        default:         return $sformatf("r?   f7=%02x f3=%0d rd=x%0d rs1=x%0d rs2=x%0d",
                                                          f7, f3, rd, rs1, rs2);
                    endcase
                end
                7'b0000011: begin                     // lw
                    imm12 = instr[31:20];
                    return $sformatf("lw   x%0d, %0d(x%0d)", rd, imm12, rs1);
                end
                7'b0100011: begin                     // sw
                    imm12 = {instr[31:25], instr[11:7]};
                    return $sformatf("sw   x%0d, %0d(x%0d)", rs2, imm12, rs1);
                end
                7'b1100011: begin                     // beq
                    imm13 = {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
                    return $sformatf("beq  x%0d, x%0d, %+0d", rs1, rs2, imm13);
                end
                default:
                    return $sformatf("?    opcode=%07b (%08x)", op, instr);
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // 源操作数打印：按指令类型分行打印寄存器操作数 / 扩展立即数（dut 与 golden 双方值）
    //--------------------------------------------------------------------------
    task automatic print_operands;
        logic [31:0] instr;
        logic [6:0]  op;
        logic [4:0]  rs1, rs2;
        begin
            instr = g_imem[cur_instr_pc[15:2]];
            op    = instr[6:0];
            rs1   = instr[19:15];
            rs2   = instr[24:20];
            case (op)
                // R 型 / beq：两个源操作数均为寄存器
                7'b0110011, 7'b1100011:
                    $display("  operands : rs1=x%0d  dut=%08x  golden=%08x ; rs2=x%0d  dut=%08x  golden=%08x",
                             rs1, cur_dut_op1, cur_g_op1, rs2, cur_dut_op2, cur_g_op2);
                // lw：基址寄存器 + 符号扩展立即数
                7'b0000011:
                    $display("  operands : rs1=x%0d  dut=%08x  golden=%08x ; imm(sext) dut=%08x  golden=%08x (%0d)",
                             rs1, cur_dut_op1, cur_g_op1,
                             cur_dut_imm, cur_g_imm, $signed(cur_g_imm));
                // sw：基址寄存器 + 符号扩展立即数 + 存储数据寄存器
                7'b0100011:
                    $display("  operands : rs1=x%0d  dut=%08x  golden=%08x ; imm(sext) dut=%08x  golden=%08x (%0d) ; data rs2=x%0d  dut=%08x  golden=%08x",
                             rs1, cur_dut_op1, cur_g_op1,
                             cur_dut_imm, cur_g_imm, $signed(cur_g_imm),
                             rs2, cur_dut_op2, cur_g_op2);
                default: ;
            endcase
        end
    endtask

    //--------------------------------------------------------------------------
    // 出错现场打印：每个出错周期只打印一次现场头，后续错误追加明细行
    //--------------------------------------------------------------------------
    task automatic print_ctx;
        begin
            if (!ctx_printed) begin
                ctx_printed = 1'b1;
                $display("------------------------------------------------------------");
                $display("[%0t] ERROR @cycle %0d", $time, cycle_cnt);
//                $display("  instr pc : %08x", cur_instr_pc);
                $display("  dut   pc : %08x    golden pc : %08x", dut.pc, g_pc);
                $display("  encoding : %08x", g_imem[cur_instr_pc[15:2]]);
                $display("  asm      : %s", disasm(g_imem[cur_instr_pc[15:2]]));
                print_operands();
            end
        end
    endtask

    task automatic bump_error;
        begin
            error_cnt++;
            if (error_cnt > 20)
                $fatal(1, "error count exceeds 20, simulation aborted");
        end
    endtask

    //--------------------------------------------------------------------------
    // 各类比对任务：不匹配时先打印出错现场，再打印该类明细
    //--------------------------------------------------------------------------
    task automatic cmp_pc(input logic [31:0] exp, input logic [31:0] got);
        begin
            cmp_cnt++;
            if (exp !== got) begin
                print_ctx();
                $display("  PC       : dut=%08x   golden=%08x", got, exp);
                bump_error();
            end
        end
    endtask

    task automatic cmp_inst(input logic [31:0] exp, input logic [31:0] got);
        begin
            cmp_cnt++;
            if (exp !== got) begin
                print_ctx();
                $display("  INST     : dut=%08x   golden=%08x", got, exp);
                bump_error();
            end
        end
    endtask

    task automatic cmp_reg(input int r,
                           input logic [31:0] exp, input logic [31:0] got);
        begin
            cmp_cnt++;
            if (exp !== got) begin
                print_ctx();
                $display("  REG x%-2d  : dut=%08x   golden=%08x", r, got, exp);
                bump_error();
            end
        end
    endtask

    task automatic cmp_dmem(input int w,
                            input logic [31:0] exp, input logic [31:0] got);
        begin
            cmp_cnt++;
            if (exp !== got) begin
                print_ctx();
                $display("  DMEM     : byte addr=%08x (word %0d)  dut=%08x   golden=%08x",
                         (w << 2), w, got, exp);
                bump_error();
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // 黄金参考模型：执行 g_pc 处的一条指令（仅 7 条目标指令）
    //--------------------------------------------------------------------------
    task automatic golden_step;
        logic [31:0] inst, a, b, addr, next_pc;
        logic [11:0] imm12;
        logic [12:0] imm13;
        logic [4:0]  rd, rs1, rs2;
        logic [13:0] widx;
        begin
            inst   = g_imem[g_pc[15:2]];
            rd     = inst[11:7];
            rs1    = inst[19:15];
            rs2    = inst[24:20];
            a      = g_regs[rs1];          // 先快照操作数，避免 rd==rs 别名影响
            b      = g_regs[rs2];
            next_pc = g_pc + 32'd4;

            // 保存操作数快照，供出错现场打印（源操作数取执行前的值）
            cur_g_op1 = a;
            cur_g_op2 = b;
            cur_g_imm = 32'd0;

            case (inst[6:0])
                //---------------- R 型：add / sub / and / or ----------------
                7'b0110011: begin
                    case ({inst[31:25], inst[14:12]})
                        {7'h00, 3'b000}: g_regs[rd] = a + b;        // add
                        {7'h20, 3'b000}: g_regs[rd] = a - b;        // sub
                        {7'h00, 3'b111}: g_regs[rd] = a & b;        // and
                        {7'h00, 3'b110}: g_regs[rd] = a | b;        // or
                        default: ;  // 发生器保证不出现
                    endcase
                end

                //---------------- I 型：lw ----------------
                7'b0000011: begin
                    imm12 = inst[31:20];
                    addr  = a + sext12(imm12);
                    cur_g_imm = sext12(imm12);        // 保存扩展立即数供出错打印
                    g_regs[rd] = g_dmem[(addr >> 2) & 32'h3FFF];
                end

                //---------------- S 型：sw ----------------
                7'b0100011: begin
                    imm12 = {inst[31:25], inst[11:7]};
                    addr  = a + sext12(imm12);
                    cur_g_imm = sext12(imm12);        // 保存扩展立即数供出错打印
                    widx  = (addr >> 2) & 32'h3FFF;
                    g_dmem[widx] = b;
                    touched[widx] = 1'b1;
                end

                //---------------- B 型：beq ----------------
                7'b1100011: begin
                    imm13 = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
                    if (a == b)
                        next_pc = g_pc + sext13(imm13);
                end

                default: ;
            endcase

            g_regs[0] = 32'd0;             // $zero 恒为 0
            g_pc      = next_pc;
        end
    endtask

    //--------------------------------------------------------------------------
    // 逐周期推进 + 比对（下降沿采样：此时上个上升沿的状态已稳定）
    // 顺序：先让黄金模型执行 g_pc 处的指令并推进，
    //       再与 DUT 比对（DUT 在上个上升沿已执行同一指令，二者同拍）
    //--------------------------------------------------------------------------
    always @(negedge clk) begin
        if (reset) begin
            // 复位期间对齐黄金模型初始状态（与 DUT 一同复位到起始地址）
            g_pc = START_PC;
            for (int r = 0; r < 32; r++) g_regs[r] = 32'd0;
            cycle_cnt = 0;
        end
        else if (cycle_cnt < MAX_CYCLES) begin
            cur_instr_pc = g_pc;           // 记录本周期执行的指令的 PC
            ctx_printed  = 1'b0;

            golden_step();                                     // 黄金模型先执行一步

            cmp_pc  (g_pc, dut.pc);                            // (1) PC
            cmp_inst(g_imem[g_pc[15:2]], dut.inst);            // (2) 指令编码

            for (int r = 0; r < 32; r++)                       // (3) 32 个寄存器
                cmp_reg(r, g_regs[r], dut.u_regfile.regs[r]);

            for (int w = 0; w < 16384; w++)                    // (4) 写过的存储器字
                if (touched[w])
                    cmp_dmem(w, g_dmem[w], dut.u_dmem.u_sram.sram[w]);

            if (verbose)
                $display("[trace] cycle=%0d pc=%08x inst=%08x", cycle_cnt, dut.pc, dut.inst);

            cycle_cnt++;
        end
    end

    //--------------------------------------------------------------------------
    // 主流程：复位 -> 运行 MAX_CYCLES -> 数据存储器最终全比对 -> 报告
    //--------------------------------------------------------------------------
    initial begin
        reset = 1'b1;
        repeat (3) @(negedge clk);
        reset = 1'b0;

        wait (cycle_cnt >= MAX_CYCLES);
        @(negedge clk);

        // 仿真结束：数据存储器 16K 全空间最终比对（逐周期只比了 touched 字）
        for (int w = 0; w < 16384; w++) begin
            cmp_cnt++;
            if (g_dmem[w] !== dut.u_dmem.u_sram.sram[w]) begin
                error_cnt++;
                $display("ERROR final dmem  byte addr=%08x (word %0d)  dut=%08x  golden=%08x",
                         (w << 2), w, dut.u_dmem.u_sram.sram[w], g_dmem[w]);
            end
        end

        $display("==================================================");
        $display("Simulation finished: start_pc = %08x, cycles = %0d, compares = %0d, errors = %0d",
                 START_PC, cycle_cnt, cmp_cnt, error_cnt);
        if (error_cnt == 0) $display("==== TEST PASSED ====");
        else                $display("==== TEST FAILED ====");
        $display("==================================================");
        $finish;
    end

endmodule
