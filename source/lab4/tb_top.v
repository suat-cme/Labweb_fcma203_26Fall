//=============================================================================
//  文件名  : tb_top.v
//  功能    : top（regfile + alu_32bit）验证环节
//  方法    :
//    1. 预载：利用 a=$zero + imm（add 通路）向 regfile 写入任意常数
//    2. 黄金模型：exp_regs[0:31] + alu_ref() 参考函数
//    3. 每周期将 32 个寄存器全部内容 + ALU 输出写入 dut_log.txt /
//       golden_log.txt，供 compare.py 文件级比对；TB 内同时实时比对
//=============================================================================

`timescale 1ns / 1ps

module tb_top;

    // ---------------------------------------------------------------
    // DUT 接口
    // ---------------------------------------------------------------
    reg         clk;
    reg         reset;
    reg  [4:0]  read_addr_1;
    reg         read_en_1;
    reg  [4:0]  read_addr_2;
    reg         read_en_2;
    reg  [4:0]  write_addr;
    reg         write_en;
    reg  [5:0]  alucontrol;
    reg  [31:0] imm;
    wire  [31:0] result;
    reg         alusrc;
    wire        zero, lt, ltu, ge, geu;

//    top dut (
//        .clk         (clk),
//        .reset       (reset),
//        .read_addr_1 (read_addr_1),
//        .read_en_1   (read_en_1),
//        .read_addr_2 (read_addr_2),
//        .read_en_2   (read_en_2),
//        .write_addr  (write_addr),
//        .write_en    (write_en),
//        .alucontrol  (alucontrol),
//        .imm         (imm),
//        .alusrc      (alusrc),
//        .zero        (zero),
//        .lt          (lt),
//        .ltu         (ltu),
//        .ge          (ge),
//        .geu         (geu)
//    );

    Top dut (
        .clk        (clk),
        .rst        (reset),
        .read_addr1 (read_addr_1),
        .read_en1   (read_en_1),
        .read_addr2 (read_addr_2),
        .read_en2   (read_en_2),
        .write_addr (write_addr),
        .wen        (write_en),
        .ALUctrl    (alucontrol),
        .Imm        (imm),
        .ALUSrc     (alusrc),
        .ALU_result (result),
        .zero       (zero),
        .lt         (lt),
        .ltu        (ltu),
        .ge         (ge),
        .geu        (geu)
    );

    // ---------------------------------------------------------------
    // 时钟 / 常量
    // ---------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    localparam CTRL_ADD = 6'b00_0010;
    localparam CTRL_SUB = 6'b00_0110;
    localparam CTRL_AND = 6'b00_0000;
    localparam CTRL_OR  = 6'b00_0001;
    localparam CTRL_XOR = 6'b00_1010;
    localparam CTRL_SLL = 6'b01_0000;
    localparam CTRL_SRL = 6'b10_0000;
    localparam CTRL_SRA = 6'b11_0000;

    // ---------------------------------------------------------------
    // 黄金模型
    // ---------------------------------------------------------------
    reg [31:0] exp_regs [0:31];

    integer errors;
    integer checks;
    integer cycle_cnt;
    integer fdut;
    integer fgold;
    integer seed;

    // ALU 参�?�函数（�????? slt 类外�????? RV32I 运算�?????
    function [31:0] alu_ref;
        input [31:0] a;
        input [31:0] b;
        input [5:0]  ctrl;
        begin
            case (ctrl[5:4])
                2'b00: begin
                    case (ctrl[3:0])
                        4'b0010:  alu_ref = a + b;
                        4'b0110:  alu_ref = a - b;
                        4'b0000:  alu_ref = a & b;
                        4'b0001:  alu_ref = a | b;
                        4'b1010:  alu_ref = a ^ b;
                        default:  alu_ref = 32'hxxxxxxxx;
                    endcase
                end
                2'b01:   alu_ref = a << b[4:0];             // sll
                2'b10:   alu_ref = a >> b[4:0];             // srl
                default: alu_ref = $signed(a) >>> b[4:0];   // sra
            endcase
        end
    endfunction

    task flag_ref;
        input  [31:0] a;
        input  [31:0] b;
        input  [5:0]  ctrl;
        output        e_zero;
        output        e_lt;
        output        e_ltu;
        integer       i;
        reg           c, cin, s, ovf;
        reg    [31:0] b2, main;
        begin
            b2 = ctrl[2] ? ~b : b;
            c  = (ctrl[5:4] == 2'b00) && ctrl[2];   // carry[0]
            for (i = 0; i < 32; i = i + 1) begin
                cin = ctrl[3] ? 1'b0 : c;
                s   = a[i] ^ b2[i] ^ cin;
                c   = (a[i] & b2[i]) | (cin & (a[i] ^ b2[i]));
                case (ctrl[1:0])
                    2'b00:   main[i] = a[i] & b2[i];
                    2'b01:   main[i] = a[i] | b2[i];
                    default: main[i] = s;
                endcase
            end
            e_zero = (main == 32'd0);
            ovf    = (a[31] ^ b[31]) & (a[31] ^ main[31]);
            e_lt   = main[31] ^ ovf;    
            e_ltu  = ~c;               
        end
    endtask

    // ---------------------------------------------------------------
    // 日志：每周期 dut_log.txt / golden_log.txt
    // ---------------------------------------------------------------
    task log_cycle;
        input [31:0] alu_res_snap;
        input        z_snap, lt_snap, ltu_snap, ge_snap, geu_snap;
        input        gz, glt, gltu, gge, ggeu;   // 黄金标志
        input [31:0] gres;                        // 黄金 result
        integer i;
        begin
            cycle_cnt = cycle_cnt + 1;
            // DUT 
            $fdisplay(fdut, "CYCLE %0d", cycle_cnt);
            for (i = 0; i < 32; i = i + 1)
                $fdisplay(fdut, "R%0d=%h", i, dut.u_regfile.regs[i]);
            $fdisplay(fdut, "ALU result=%h zero=%b lt=%b ltu=%b ge=%b geu=%b",
                      alu_res_snap, z_snap, lt_snap, ltu_snap, ge_snap, geu_snap);
            // GOLDEN 
            $fdisplay(fgold, "CYCLE %0d", cycle_cnt);
            for (i = 0; i < 32; i = i + 1)
                $fdisplay(fgold, "R%0d=%h", i, exp_regs[i]);
            $fdisplay(fgold, "ALU result=%h zero=%b lt=%b ltu=%b ge=%b geu=%b",
                      gres, gz, glt, gltu, gge, ggeu);
        end
    endtask

    // ---------------------------------------------------------------
    // Debug 转储：出错时打印 DUT 全部输入/输出、regfile 两个读口输出值
    // ALU 两个输入和 result，便于定位问题
    // ---------------------------------------------------------------
    task dump_debug;
        begin
//            $display("ERROR in (cycle %0d)! Test [%0s]. Unmatched ALU results.", cycle_cnt, tag);
            $display("  ------ DEBUG @ cycle %0d (time %0t) ----", cycle_cnt, $time);
            $display("  DUT inputs: read_addr_1 = %0d, read_en_1 = %b | read_addr_2 = %0d, read_en_2 = %b | write_addr = %0d, write_en = %b | alucontrol = %b, imm = %h, alusrc = %b",
                     read_addr_1, read_en_1, read_addr_2, read_en_2,
                     write_addr, write_en, alucontrol, imm, alusrc);

            $display("  regfile out: read_data_1 = %h, read_data_2 = %h",
                     dut.read_data1, dut.read_data2);
            $display("  alu input: a = %h, b = %h",
                     dut.u_ALU.input_A, dut.u_ALU.input_B);
            $display("  DUT outputs: alu result = %h", dut.ALU_result);            
            $display("  DUT output flags: zero = %b, lt = %b, ltu = %b, ge = %b, geu = %b",
                     zero, lt, ltu, ge, geu);
            $display("  ----------------------------------------");
        end
    endtask

    // ---------------------------------------------------------------
    // 实时比对：全部寄存器 + （仅分支指令的）标志
    // ---------------------------------------------------------------
    task check_regs;
        input [8*32:1] tag;
        integer i;
        reg     dumped;
        begin
            dumped = 0;
            for (i = 0; i < 32; i = i + 1) begin
                checks = checks + 1;
                if (dut.u_regfile.regs[i] !== exp_regs[i]) begin
                    errors = errors + 1;
                    $display("ERROR in (cycle %0d)! Test [%0s]. Unmatched regs[%0d]: dut = %h exp = %h ",
                             cycle_cnt, tag, i, dut.u_regfile.regs[i], exp_regs[i] );
                    if (!dumped) begin
                        dump_debug;
                        dumped = 1;
                    end
                end
            end
        end
    endtask

    // 仅在 beq/bne/blt/bge/bltu/bgeu（ctrl=00_0110 且不写回）时调用
    task check_flags;
        input [8*32:1] tag;
        input          ez, elt, eltu;
        reg            dumped;
        begin
            dumped = 0;
            checks = checks + 1;
            if (zero !== ez) begin
                errors = errors + 1;
                $display("ERROR [%0s] zero: dut=%b exp=%b", tag, zero, ez);
                if (!dumped) begin dump_debug; dumped = 1; end
            end
            checks = checks + 1;
            if (lt !== elt) begin
                errors = errors + 1;
                $display("ERROR [%0s] lt: dut=%b exp=%b", tag, lt, elt);
                if (!dumped) begin dump_debug; dumped = 1; end
            end
            checks = checks + 1;
            if (ltu !== eltu) begin
                errors = errors + 1;
                $display("ERROR [%0s] ltu: dut=%b exp=%b", tag, ltu, eltu);
                if (!dumped) begin dump_debug; dumped = 1; end
            end
            checks = checks + 1;
            if (ge !== ~elt) begin
                errors = errors + 1;
                $display("ERROR [%0s] ge: dut=%b exp=%b", tag, ge, ~elt);
                if (!dumped) begin dump_debug; dumped = 1; end
            end
            checks = checks + 1;
            if (geu !== ~eltu) begin
                errors = errors + 1;
                $display("ERROR [%0s] geu: dut=%b exp=%b", tag, geu, ~eltu);
                if (!dumped) begin dump_debug; dumped = 1; end
            end
        end
    endtask

    // ---------------------------------------------------------------
    // 预载：经 add 通路将 data 写入 regfile[addr]（a=$zero, b=imm)
    // ---------------------------------------------------------------
    task preload;
        input [4:0]  addr;
        input [31:0] data;
        reg          ez, elt, eltu;
        begin
            @(negedge clk);
            read_addr_1 = 5'd0; read_en_1 = 1'b1;   // $zero -> a
            read_addr_2 = 5'd0; read_en_2 = 1'b0;
            alusrc      = 1'b1;  imm = data;         // b = imm
            alucontrol  = CTRL_ADD;
            write_addr  = addr;  write_en = 1'b1;
            #1;
            flag_ref(32'd0, data, CTRL_ADD, ez, elt, eltu);
            @(posedge clk); #1;
            write_en = 1'b0;
            if (addr != 5'd0) exp_regs[addr] = data;   // $zero 写被忽略
            log_cycle(dut.ALU_result, zero, lt, ltu, ge, geu,
                      ez, elt, eltu, ~elt, ~eltu, data);
            check_regs("preload");
        end
    endtask

    // ---------------------------------------------------------------
    // 执行阶段 ALU 运算并写回
    //   rs1v/rs2v 为寄存器地址；use_imm=1 , b = immv
    //   wen=0 用于分支类（只查标志不写回）
    // ---------------------------------------------------------------
    task run_op;
        input [8*32:1] tag;
        input [4:0]    rs1v;
        input [4:0]    rs2v;
        input          use_imm;
        input [31:0]   immv;
        input [5:0]    ctrl;
        input [4:0]    rd;
        input          wen;
        input          flag_chk;   // 1: beq/bne/blt/bge/bltu/bgeu, check flags
        reg [31:0] av, bv, gres;
        reg        ez, elt, eltu;
        reg [31:0] res_snap;
        reg        z_snap, lt_snap, ltu_snap, ge_snap, geu_snap;
        begin
            @(negedge clk);
            read_addr_1 = rs1v; read_en_1 = 1'b1;
            read_addr_2 = rs2v; read_en_2 = 1'b1;
            alusrc      = use_imm; imm = immv;
            alucontrol  = ctrl;
            write_addr  = rd;    write_en = wen;
            #1;   // 组合逻辑稳定
            av   = exp_regs[rs1v];
            bv   = use_imm ? immv : exp_regs[rs2v];
            gres = alu_ref(av, bv, ctrl);
            flag_ref(av, bv, ctrl, ez, elt, eltu);
            // 写沿前：直接比对
            checks = checks + 1;
            if (dut.ALU_result !== gres) begin
                errors = errors + 1;
                $display("ERROR in (cycle %0d)! Test [%0s]. Unmatched ALU result: dut = %h exp = %h (exp: a = %h, b = %h, aluctrl = %b)",
                        cycle_cnt, tag, dut.ALU_result, gres, av, bv, ctrl);
                dump_debug;
            end
            if (flag_chk) check_flags(tag, ez, elt, eltu);
            // 写沿前快照 ALU 输出（写回后 rd 可能改变 a/b，导致 result 变化）
            res_snap  = dut.ALU_result;
            z_snap    = zero;  lt_snap = lt;  ltu_snap = ltu;
            ge_snap   = ge;    geu_snap = geu;
            @(posedge clk); #1;
            write_en = 1'b0;
            if (wen && rd != 5'd0) exp_regs[rd] = gres;
            log_cycle(res_snap, z_snap, lt_snap, ltu_snap, ge_snap, geu_snap,
                      ez, elt, eltu, ~elt, ~eltu, gres);
            check_regs(tag);
        end
    endtask

    // ---------------------------------------------------------------
    // 主测试流程
    // ---------------------------------------------------------------
    integer k;
    reg [31:0] r_a, r_b;
    reg [4:0]  r_rs1, r_rs2, r_rd;
    reg [5:0]  ctrls [0:7];
    reg        r_imm_sel;

    initial begin
        errors = 0; checks = 0; cycle_cnt = 0; seed = 32'hdead_beef;
        fdut  = $fopen("dut_log.txt",    "w");
        fgold = $fopen("golden_log.txt", "w");

        // 控制码表（随机回归用，排除移位之外的组合也在内）
        ctrls[0] = CTRL_ADD; ctrls[1] = CTRL_SUB; ctrls[2] = CTRL_AND;
        ctrls[3] = CTRL_OR;  ctrls[4] = CTRL_XOR; ctrls[5] = CTRL_SLL;
        ctrls[6] = CTRL_SRL; ctrls[7] = CTRL_SRA;

        // ---- R1: 复位 ----
        reset = 1'b1;
        read_en_1 = 0; read_en_2 = 0; write_en = 0;
        read_addr_1 = 0; read_addr_2 = 0; write_addr = 0;
        alucontrol = CTRL_ADD; imm = 0; alusrc = 0;
        repeat (3) @(posedge clk);
        #1;
        reset = 1'b0;
        for (k = 0; k < 32; k = k + 1) exp_regs[k] = 32'd0;
        // 复位 a=0, b=0, ctrl=ADD -> sum=0: zero=1, lt=0, ltu=1
        begin : reset_check
            reg rz, rlt, rltu;
            flag_ref(32'd0, 32'd0, CTRL_ADD, rz, rlt, rltu);
            log_cycle(dut.ALU_result, zero, lt, ltu, ge, geu,
                      rz, rlt, rltu, ~rlt, ~rltu, 32'd0);
        end
        check_regs("reset");

        // ---- R2: 预载边界数据 ----
        preload(5'd1,  32'h0000_0000);
        preload(5'd2,  32'h0000_0001);
        preload(5'd3,  32'hFFFF_FFFF);
        preload(5'd4,  32'h8000_0000);
        preload(5'd5,  32'h7FFF_FFFF);
        preload(5'd6,  32'hAAAA_AAAA);
        preload(5'd7,  32'h5555_5555);
        preload(5'd8,  32'h1234_5678);
        preload(5'd9,  32'd31);
        preload(5'd10, 32'd32);        // 移位量低 5 位 = 0
        preload(5'd11, 32'hFFFF_FFE0); // 移位量低 5 位 = 0
        preload(5'd12, 32'h00FF_00FF);
        preload(5'd13, $random(seed));
        preload(5'd14, $random(seed));
        preload(5'd15, $random(seed));

        // ---- R3: 若 $zero 写非 0，应被忽略 ----
        preload(5'd0,  32'hDEAD_BEEF);

        // ---- A1: add（regfile 通路 + imm 通路）----
        run_op("add_r8_r2",   5'd8, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd16, 1'b1, 1'b0);
        run_op("add_7fff_1",  5'd5, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd17, 1'b1, 1'b0); // 0x7FFFFFFF+1
        run_op("add_ffff_1",  5'd3, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd18, 1'b1, 1'b0); // 无符号回�?????
        run_op("add_8000s",   5'd4, 5'd4, 1'b0, 32'd0, CTRL_ADD, 5'd19, 1'b1, 1'b0); // 0x80000000+0x80000000
        run_op("addi_imm",    5'd8, 5'd0, 1'b1, 32'h0000_0100, CTRL_ADD, 5'd20, 1'b1, 1'b0);
        run_op("addi_neg",    5'd1, 5'd0, 1'b1, 32'hFFFF_FFFF, CTRL_ADD, 5'd21, 1'b1, 1'b0); // 0 + (-1)

        // ---- A2: sub ----
        run_op("sub_0_0",     5'd1, 5'd1, 1'b0, 32'd0, CTRL_SUB, 5'd22, 1'b1, 1'b0); // zero=1
        run_op("sub_0_1",     5'd1, 5'd2, 1'b0, 32'd0, CTRL_SUB, 5'd23, 1'b1, 1'b0);
        run_op("sub_8000_1",  5'd4, 5'd2, 1'b0, 32'd0, CTRL_SUB, 5'd24, 1'b1, 1'b0);
        run_op("sub_7fff_ff", 5'd5, 5'd3, 1'b0, 32'd0, CTRL_SUB, 5'd25, 1'b1, 1'b0);
        run_op("subi",        5'd8, 5'd0, 1'b1, 32'h0000_0001, CTRL_SUB, 5'd26, 1'b1, 1'b0);

        // ---- A3: and ----
        run_op("and_f_f",     5'd3, 5'd3, 1'b0, 32'd0, CTRL_AND, 5'd27, 1'b1, 1'b0);
        run_op("and_f_0",     5'd3, 5'd1, 1'b0, 32'd0, CTRL_AND, 5'd28, 1'b1, 1'b0);
        run_op("and_aa_55",   5'd6, 5'd7, 1'b0, 32'd0, CTRL_AND, 5'd29, 1'b1, 1'b0); // = 0
        run_op("andi",        5'd8, 5'd0, 1'b1, 32'h0000_FFFF, CTRL_AND, 5'd30, 1'b1, 1'b0);

        // ---- A4: or ----
        run_op("or_0_0",      5'd1, 5'd1, 1'b0, 32'd0, CTRL_OR, 5'd31, 1'b1, 1'b0);
        run_op("or_aa_55",    5'd6, 5'd7, 1'b0, 32'd0, CTRL_OR, 5'd16, 1'b1, 1'b0);  // = �?????1（覆�????? r16�?????
        run_op("ori",         5'd8, 5'd0, 1'b1, 32'hFFFF_0000, CTRL_OR, 5'd17, 1'b1, 1'b0);

        // ---- A5: xor ----
        run_op("xor_same",    5'd8, 5'd8, 1'b0, 32'd0, CTRL_XOR, 5'd18, 1'b1, 1'b0); // a^a=0
        run_op("xor_zero",    5'd8, 5'd1, 1'b0, 32'd0, CTRL_XOR, 5'd19, 1'b1, 1'b0); // a^0=a
        run_op("xori",        5'd8, 5'd0, 1'b1, 32'hFFFF_FFFF, CTRL_XOR, 5'd20, 1'b1, 1'b0);

        // ---- S1: sll（移位量只取�????? 5 位）----
        run_op("sll_0",       5'd8, 5'd1, 1'b0, 32'd0, CTRL_SLL, 5'd21, 1'b1, 1'b0); // shamt=0
        run_op("sll_1",       5'd8, 5'd2, 1'b0, 32'd0, CTRL_SLL, 5'd22, 1'b1, 1'b0); // shamt=1
        run_op("sll_31",      5'd8, 5'd9, 1'b0, 32'd0, CTRL_SLL, 5'd23, 1'b1, 1'b0); // shamt=31
        run_op("sll_32",      5'd8, 5'd10, 1'b0, 32'd0, CTRL_SLL, 5'd24, 1'b1, 1'b0); // 32 -> shamt=0
        run_op("sll_e0",      5'd8, 5'd11, 1'b0, 32'd0, CTRL_SLL, 5'd25, 1'b1, 1'b0); // 0xFFFFFFE0 -> shamt=0
        run_op("slli_31",     5'd3, 5'd0, 1'b1, 32'h0000_00FF, CTRL_SLL, 5'd26, 1'b1, 1'b0); // imm �?????5�?????=31

        // ---- S2: srl ----
        run_op("srl_8000_1",  5'd4, 5'd2, 1'b0, 32'd0, CTRL_SRL, 5'd27, 1'b1, 1'b0); // 高位�?????0
        run_op("srl_f_31",    5'd3, 5'd9, 1'b0, 32'd0, CTRL_SRL, 5'd28, 1'b1, 1'b0);
        run_op("srl_32",      5'd8, 5'd10, 1'b0, 32'd0, CTRL_SRL, 5'd29, 1'b1, 1'b0); // -> shamt=0
        run_op("srli",        5'd4, 5'd0, 1'b1, 32'd4, CTRL_SRL, 5'd30, 1'b1, 1'b0);

        // ---- S3: sra ----
        run_op("sra_8000_1",  5'd4, 5'd2, 1'b0, 32'd0, CTRL_SRA, 5'd31, 1'b1, 1'b0); // 符号扩展
        run_op("sra_f_31",    5'd3, 5'd9, 1'b0, 32'd0, CTRL_SRA, 5'd16, 1'b1, 1'b0);
        run_op("sra_pos",     5'd8, 5'd2, 1'b0, 32'd0, CTRL_SRA, 5'd17, 1'b1, 1'b0); // 正数==srl
        run_op("srai",        5'd4, 5'd0, 1'b1, 32'd31, CTRL_SRA, 5'd18, 1'b1, 1'b0);

        // ---- B1/B2/B3: 分支标志（write_en=0，不写回�?????----
        run_op("beq_eq",      5'd3, 5'd3, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1); // zero=1
        run_op("beq_ne",      5'd8, 5'd2, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1);
        run_op("blt_neg_pos", 5'd4, 5'd5, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1); // 有符�????? 0x80000000<0x7FFFFFFF
        run_op("blt_m1_1",    5'd3, 5'd2, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1); // -1 < 1
        run_op("blt_pos_neg", 5'd5, 5'd4, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1); // �?????<�????? 不成�?????
        run_op("bltu_f_1",    5'd3, 5'd2, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1); // 无符�????? 0xFFFFFFFF>1
        run_op("bltu_0_f",    5'd1, 5'd3, 1'b0, 32'd0, CTRL_SUB, 5'd0, 1'b0, 1'b1); // 0 < 0xFFFFFFFF

        // ---- G2/G3/G4: 源目的同寄存�????? ----
        run_op("add_r8_r8",   5'd8, 5'd8, 1'b0, 32'd0, CTRL_ADD, 5'd8, 1'b1, 1'b0);  // rd=rs1=rs2
        run_op("add_r8_r2_r8",5'd8, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd8, 1'b1, 1'b0);  // rd==rs1
        run_op("sub_r2_r8_r8",5'd2, 5'd8, 1'b0, 32'd0, CTRL_SUB, 5'd8, 1'b1, 1'b0);  // rd==rs2

        // ---- G5: $zero 作源 ----
        run_op("add_z_r2",    5'd0, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd19, 1'b1, 1'b0); // rs1=$zero
        run_op("add_r2_z",    5'd2, 5'd0, 1'b0, 32'd0, CTRL_ADD, 5'd20, 1'b1, 1'b0); // rs2=$zero

        // ---- G6: $zero 作目的（写入忽略�?????----
        run_op("add_to_zero", 5'd8, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd0, 1'b1, 1'b0);

        // ---- G7: 同周期读写同地址（读旧�?�）----
        // r21 当前�????? 0+(-1)=0xFFFFFFFF；再执行 r21 = r21 + 1，读到的应为旧�??
        run_op("rw_same",     5'd21, 5'd2, 1'b0, 32'd0, CTRL_ADD, 5'd21, 1'b1, 1'b0);

        // ---- 随机回归 ----
        for (k = 0; k < 50; k = k + 1) begin
            r_rs1 = $random(seed) & 31;
            r_rs2 = $random(seed) & 31;
            r_rd  = $random(seed) & 31;
            r_a   = $random(seed);
            r_imm_sel = $random(seed) & 1;
            // 预载随机值到随机源寄存器，再执行随机操作
            preload(r_rs1, r_a);
            r_b = $random(seed);
            preload(r_rs2, r_b);
            run_op("random", r_rs1, r_rs2, r_imm_sel, $random(seed),
                   ctrls[$random(seed) & 7], r_rd, 1'b1, 1'b0);
        end

        // ---- 汇�?? ----
        $display("================================================");
        $display("checks = %0d, errors = %0d", checks, errors);
        if (errors == 0) begin
            $display("TEST PASSED !");
            $display("All test stimuli passed.");
        end
        else             $display("TEST FAILED !");
        $display("================================================");

        $fclose(fdut);
        $fclose(fgold);
        #1000
        $finish;
    end

endmodule
