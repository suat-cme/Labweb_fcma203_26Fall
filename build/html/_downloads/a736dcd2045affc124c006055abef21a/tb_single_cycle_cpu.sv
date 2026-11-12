`timescale 1ns / 1ps

module tb_single_cycle_cpu;

    localparam integer MEM_WORDS       = 16384;
    localparam integer MAX_ERRORS      = 10;
    localparam integer MAX_INSTRUCTIONS = 20000;
    localparam integer RANDOM_ALU_COUNT = 400;
    localparam integer RANDOM_MEM_COUNT = 200;
    localparam integer RANDOM_BRANCH_COUNT = 60;
    localparam [31:0] END_INSTRUCTION  = 32'h0000006f; // jal x0, 0

    reg         clk;
    reg         reset;
    reg  [31:0] start_pc;

    single_cycle_cpu dut (
        .clk      (clk),
        .reset    (reset),
        .start_pc (start_pc)
    );

    always #5 clk = ~clk;

    // Independent architectural reference state.
    reg [31:0] ref_pc;
    reg [31:0] ref_regs [0:31];
    reg [31:0] ref_imem [0:MEM_WORDS-1];
    reg [31:0] ref_dmem [0:MEM_WORDS-1];
    reg [31:0] program_mem [0:MEM_WORDS-1];

    integer program_count;
    integer end_pc;
    integer errors;
    integer executed_count;
    integer i;

    // Metadata for the instruction currently being checked.
    reg [31:0] cur_pc;
    reg [31:0] cur_inst;
    string     cur_assembly;
    reg [31:0] cur_src1;
    reg [31:0] cur_src2;
    reg [31:0] cur_imm;
    reg [31:0] cur_dut_src1;
    reg [31:0] cur_dut_src2;
    reg [31:0] cur_dut_imm;
    reg [31:0] cur_dut_pc;
    reg        cur_mem_access;
    reg [31:0] cur_mem_addr;

    // Instruction encoders used by the stimulus generator.
    function automatic [31:0] enc_r;
        input [6:0] f7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        begin
            enc_r = {f7, rs2, rs1, f3, rd, 7'b0110011};
        end
    endfunction

    function automatic [31:0] enc_i;
        input [11:0] imm12;
        input [4:0] rs1;
        input [2:0] f3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_i = {imm12, rs1, f3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm12;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        begin
            enc_s = {imm12[11:5], rs2, rs1, f3, imm12[4:0], 7'b0100011};
        end
    endfunction

    function automatic [31:0] enc_b;
        input [12:0] imm13;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        begin
            enc_b = {imm13[12], imm13[10:5], rs2, rs1, f3,
                     imm13[4:1], imm13[11], 7'b1100011};
        end
    endfunction

    function automatic [31:0] enc_u;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_u = {imm20, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_j;
        input [20:0] imm21;
        input [4:0] rd;
        begin
            enc_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12],
                     rd, 7'b1101111};
        end
    endfunction

    task automatic emit;
        input [31:0] instruction;
        begin
            if (program_count >= MEM_WORDS) begin
                $display("ERROR: Test program exceeds instruction memory capacity.");
                $fatal(1);
                $finish;
            end
            program_mem[program_count] = instruction;
            program_count = program_count + 1;
        end
    endtask

    task automatic patch_b;
        input integer index;
        input [12:0] offset;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] f3;
        begin
            program_mem[index] = enc_b(offset, rs2, rs1, f3);
        end
    endtask

    task automatic patch_j;
        input integer index;
        input [20:0] offset;
        input [4:0] rd;
        begin
            program_mem[index] = enc_j(offset, rd);
        end
    endtask

    // Disassembly is used only for diagnostics, not for reference execution.
    function automatic string disassemble;
        input [31:0] instruction;
        reg [6:0] opcode;
        reg [2:0] f3;
        reg [6:0] f7;
        reg [4:0] rd;
        reg [4:0] rs1;
        reg [4:0] rs2;
        reg [31:0] imm;
        begin
            opcode = instruction[6:0];
            rd     = instruction[11:7];
            f3     = instruction[14:12];
            rs1    = instruction[19:15];
            rs2    = instruction[24:20];
            f7     = instruction[31:25];
            imm    = 32'd0;
            disassemble = $sformatf(".word 0x%08h", instruction);

            case (opcode)
                7'b0110111: disassemble = $sformatf("lui x%0d, 0x%05h", rd, instruction[31:12]);
                7'b0010111: disassemble = $sformatf("auipc x%0d, 0x%05h", rd, instruction[31:12]);
                7'b0110011: begin
                    case (f3)
                        3'b000: disassemble = (f7 == 7'b0100000) ?
                            $sformatf("sub x%0d, x%0d, x%0d", rd, rs1, rs2) :
                            $sformatf("add x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b001: disassemble = $sformatf("sll x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b010: disassemble = $sformatf("slt x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b011: disassemble = $sformatf("sltu x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b100: disassemble = $sformatf("xor x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b101: disassemble = (f7 == 7'b0100000) ?
                            $sformatf("sra x%0d, x%0d, x%0d", rd, rs1, rs2) :
                            $sformatf("srl x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b110: disassemble = $sformatf("or x%0d, x%0d, x%0d", rd, rs1, rs2);
                        3'b111: disassemble = $sformatf("and x%0d, x%0d, x%0d", rd, rs1, rs2);
                    endcase
                end
                7'b0010011: begin
                    imm = {{20{instruction[31]}}, instruction[31:20]};
                    case (f3)
                        3'b000: disassemble = $sformatf("addi x%0d, x%0d, %0d", rd, rs1, $signed(imm));
                        3'b010: disassemble = $sformatf("slti x%0d, x%0d, %0d", rd, rs1, $signed(imm));
                        3'b011: disassemble = $sformatf("sltiu x%0d, x%0d, %0d", rd, rs1, $signed(imm));
                        3'b100: disassemble = $sformatf("xori x%0d, x%0d, %0d", rd, rs1, $signed(imm));
                        3'b110: disassemble = $sformatf("ori x%0d, x%0d, %0d", rd, rs1, $signed(imm));
                        3'b111: disassemble = $sformatf("andi x%0d, x%0d, %0d", rd, rs1, $signed(imm));
                        3'b001: disassemble = $sformatf("slli x%0d, x%0d, %0d", rd, rs1, rs2);
                        3'b101: disassemble = (f7 == 7'b0100000) ?
                            $sformatf("srai x%0d, x%0d, %0d", rd, rs1, rs2) :
                            $sformatf("srli x%0d, x%0d, %0d", rd, rs1, rs2);
                    endcase
                end
                7'b0000011: begin
                    imm = {{20{instruction[31]}}, instruction[31:20]};
                    case (f3)
                        3'b000: disassemble = $sformatf("lb x%0d, %0d(x%0d)", rd, $signed(imm), rs1);
                        3'b001: disassemble = $sformatf("lh x%0d, %0d(x%0d)", rd, $signed(imm), rs1);
                        3'b010: disassemble = $sformatf("lw x%0d, %0d(x%0d)", rd, $signed(imm), rs1);
                        3'b100: disassemble = $sformatf("lbu x%0d, %0d(x%0d)", rd, $signed(imm), rs1);
                        3'b101: disassemble = $sformatf("lhu x%0d, %0d(x%0d)", rd, $signed(imm), rs1);
                    endcase
                end
                7'b0100011: begin
                    imm = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
                    case (f3)
                        3'b000: disassemble = $sformatf("sb x%0d, %0d(x%0d)", rs2, $signed(imm), rs1);
                        3'b001: disassemble = $sformatf("sh x%0d, %0d(x%0d)", rs2, $signed(imm), rs1);
                        3'b010: disassemble = $sformatf("sw x%0d, %0d(x%0d)", rs2, $signed(imm), rs1);
                    endcase
                end
                7'b1100011: begin
                    imm = {{19{instruction[31]}}, instruction[31], instruction[7],
                           instruction[30:25], instruction[11:8], 1'b0};
                    case (f3)
                        3'b000: disassemble = $sformatf("beq x%0d, x%0d, %0d", rs1, rs2, $signed(imm));
                        3'b001: disassemble = $sformatf("bne x%0d, x%0d, %0d", rs1, rs2, $signed(imm));
                        3'b100: disassemble = $sformatf("blt x%0d, x%0d, %0d", rs1, rs2, $signed(imm));
                        3'b101: disassemble = $sformatf("bge x%0d, x%0d, %0d", rs1, rs2, $signed(imm));
                        3'b110: disassemble = $sformatf("bltu x%0d, x%0d, %0d", rs1, rs2, $signed(imm));
                        3'b111: disassemble = $sformatf("bgeu x%0d, x%0d, %0d", rs1, rs2, $signed(imm));
                    endcase
                end
                7'b1101111: begin
                    imm = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                           instruction[20], instruction[30:21], 1'b0};
                    disassemble = $sformatf("jal x%0d, %0d", rd, $signed(imm));
                end
                7'b1100111: begin
                    imm = {{20{instruction[31]}}, instruction[31:20]};
                    disassemble = $sformatf("jalr x%0d, %0d(x%0d)", rd, $signed(imm), rs1);
                end
            endcase
        end
    endfunction

    task automatic ref_write;
        input [4:0] rd;
        input [31:0] value;
        begin
            if (rd != 5'd0)
                ref_regs[rd] = value;
            ref_regs[0] = 32'd0;
        end
    endtask

    function automatic [31:0] ref_load;
        input [31:0] address;
        input [2:0] f3;
        reg [31:0] word_data;
        reg [31:0] shifted;
        begin
            word_data = ref_dmem[address[15:2]];
            shifted = word_data >> {address[1:0], 3'b000};
            case (f3)
                3'b000: ref_load = {{24{shifted[7]}}, shifted[7:0]};
                3'b001: ref_load = {{16{shifted[15]}}, shifted[15:0]};
                3'b010: ref_load = word_data;
                3'b100: ref_load = {24'd0, shifted[7:0]};
                3'b101: ref_load = {16'd0, shifted[15:0]};
                default: ref_load = 32'd0;
            endcase
        end
    endfunction

    task automatic ref_store;
        input [31:0] address;
        input [2:0] f3;
        input [31:0] value;
        integer word_index;
        begin
            word_index = address[15:2];
            case (f3)
                3'b000: begin
                    case (address[1:0])
                        2'd0: ref_dmem[word_index][7:0]   = value[7:0];
                        2'd1: ref_dmem[word_index][15:8]  = value[7:0];
                        2'd2: ref_dmem[word_index][23:16] = value[7:0];
                        2'd3: ref_dmem[word_index][31:24] = value[7:0];
                    endcase
                end
                3'b001: begin
                    if (address[1:0] == 2'd0)
                        ref_dmem[word_index][15:0] = value[15:0];
                    else if (address[1:0] == 2'd2)
                        ref_dmem[word_index][31:16] = value[15:0];
                end
                3'b010: begin
                    if (address[1:0] == 2'd0)
                        ref_dmem[word_index] = value;
                end
            endcase
        end
    endtask

    // Execute exactly one instruction using only the reference state.
    task automatic ref_step;
        reg [6:0] opcode;
        reg [2:0] f3;
        reg [6:0] f7;
        reg [4:0] rd;
        reg [4:0] rs1;
        reg [4:0] rs2;
        reg [31:0] src1;
        reg [31:0] src2;
        reg signed [31:0] signed_src1;
        reg [31:0] imm_i;
        reg [31:0] imm_s;
        reg [31:0] imm_b;
        reg [31:0] imm_u;
        reg [31:0] imm_j;
        reg [31:0] next_pc;
        reg [31:0] result;
        reg [31:0] address;
        reg [31:0] selected_imm;
        begin
            opcode = cur_inst[6:0];
            rd     = cur_inst[11:7];
            f3     = cur_inst[14:12];
            rs1    = cur_inst[19:15];
            rs2    = cur_inst[24:20];
            f7     = cur_inst[31:25];
            src1   = ref_regs[rs1];
            src2   = ref_regs[rs2];
            signed_src1 = src1;
            imm_i  = {{20{cur_inst[31]}}, cur_inst[31:20]};
            imm_s  = {{20{cur_inst[31]}}, cur_inst[31:25], cur_inst[11:7]};
            imm_b  = {{19{cur_inst[31]}}, cur_inst[31], cur_inst[7],
                      cur_inst[30:25], cur_inst[11:8], 1'b0};
            imm_u  = {cur_inst[31:12], 12'b0};
            imm_j  = {{11{cur_inst[31]}}, cur_inst[31], cur_inst[19:12],
                      cur_inst[20], cur_inst[30:21], 1'b0};
            next_pc = cur_pc + 32'd4;
            result = 32'd0;
            address = 32'd0;
            selected_imm = 32'd0;
            cur_mem_access = 1'b0;
            cur_mem_addr = 32'd0;
            cur_src1 = src1;
            cur_src2 = src2;

            case (opcode)
                7'b0110111: begin // LUI
                    selected_imm = imm_u;
                    ref_write(rd, imm_u);
                end
                7'b0010111: begin // AUIPC
                    selected_imm = imm_u;
                    ref_write(rd, cur_pc + imm_u);
                end
                7'b0110011: begin // OP
                    case (f3)
                        3'b000: result = (f7 == 7'b0100000) ? src1 - src2 : src1 + src2;
                        3'b001: result = src1 << src2[4:0];
                        3'b010: result = {31'd0, ($signed(src1) < $signed(src2))};
                        3'b011: result = {31'd0, (src1 < src2)};
                        3'b100: result = src1 ^ src2;
                        3'b101: begin
                            if (f7 == 7'b0100000)
                                result = signed_src1 >>> src2[4:0];
                            else
                                result = src1 >> src2[4:0];
                        end
                        3'b110: result = src1 | src2;
                        3'b111: result = src1 & src2;
                    endcase
                    ref_write(rd, result);
                end
                7'b0010011: begin // OP-IMM
                    selected_imm = imm_i;
                    case (f3)
                        3'b000: result = src1 + imm_i;
                        3'b001: result = src1 << cur_inst[24:20];
                        3'b010: result = {31'd0, ($signed(src1) < $signed(imm_i))};
                        3'b011: result = {31'd0, (src1 < imm_i)};
                        3'b100: result = src1 ^ imm_i;
                        3'b101: begin
                            if (f7 == 7'b0100000)
                                result = signed_src1 >>> cur_inst[24:20];
                            else
                                result = src1 >> cur_inst[24:20];
                        end
                        3'b110: result = src1 | imm_i;
                        3'b111: result = src1 & imm_i;
                    endcase
                    ref_write(rd, result);
                end
                7'b0000011: begin // LOAD
                    selected_imm = imm_i;
                    address = src1 + imm_i;
                    result = ref_load(address, f3);
                    ref_write(rd, result);
                    cur_mem_access = 1'b1;
                    cur_mem_addr = address;
                end
                7'b0100011: begin // STORE
                    selected_imm = imm_s;
                    address = src1 + imm_s;
                    ref_store(address, f3, src2);
                    cur_mem_access = 1'b1;
                    cur_mem_addr = address;
                end
                7'b1100011: begin // BRANCH
                    selected_imm = imm_b;
                    case (f3)
                        3'b000: if (src1 == src2) next_pc = cur_pc + imm_b;
                        3'b001: if (src1 != src2) next_pc = cur_pc + imm_b;
                        3'b100: if ($signed(src1) < $signed(src2)) next_pc = cur_pc + imm_b;
                        3'b101: if ($signed(src1) >= $signed(src2)) next_pc = cur_pc + imm_b;
                        3'b110: if (src1 < src2) next_pc = cur_pc + imm_b;
                        3'b111: if (src1 >= src2) next_pc = cur_pc + imm_b;
                        default: next_pc = cur_pc + 32'd4;
                    endcase
                end
                7'b1101111: begin // JAL
                    selected_imm = imm_j;
                    ref_write(rd, cur_pc + 32'd4);
                    next_pc = cur_pc + imm_j;
                end
                7'b1100111: begin // JALR
                    selected_imm = imm_i;
                    next_pc = (src1 + imm_i) & 32'hfffffffe;
                    ref_write(rd, cur_pc + 32'd4);
                end
                default: begin
                    next_pc = cur_pc + 32'd4;
                end
            endcase

            cur_imm = selected_imm;
            ref_pc = next_pc;
            ref_regs[0] = 32'd0;
        end
    endtask


    task automatic print_source_operands;
        reg [6:0] opcode;
        reg [2:0] f3;
        begin
            opcode = cur_inst[6:0];
            f3 = cur_inst[14:12];
            case (opcode)
                7'b0110011: begin
                    $display("  REF source rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_src1);
                    $display("  DUT source rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_dut_src1);
                    $display("  REF source rs2=x%0d, value=0x%08h", cur_inst[24:20], cur_src2);
                    $display("  DUT source rs2=x%0d, value=0x%08h", cur_inst[24:20], cur_dut_src2);
                end
                7'b0010011: begin
                    $display("  REF source rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_src1);
                    $display("  DUT source rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_dut_src1);
                    if ((f3 == 3'b001) || (f3 == 3'b101))
                        $display("  Shift amount=%0d", cur_inst[24:20]);
                    $display("  REF extended immediate=0x%08h (%0d)", cur_imm, $signed(cur_imm));
                    $display("  DUT extended immediate=0x%08h (%0d)", cur_dut_imm, $signed(cur_dut_imm));
                end
                7'b0000011, 7'b1100111: begin
                    $display("  REF source rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_src1);
                    $display("  DUT source rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_dut_src1);
                    $display("  REF extended immediate=0x%08h (%0d)", cur_imm, $signed(cur_imm));
                    $display("  DUT extended immediate=0x%08h (%0d)", cur_dut_imm, $signed(cur_dut_imm));
                end
                7'b0100011: begin
                    $display("  REF base rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_src1);
                    $display("  DUT base rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_dut_src1);
                    $display("  REF store data rs2=x%0d, value=0x%08h", cur_inst[24:20], cur_src2);
                    $display("  DUT store data rs2=x%0d, value=0x%08h", cur_inst[24:20], cur_dut_src2);
                    $display("  REF extended immediate=0x%08h (%0d)", cur_imm, $signed(cur_imm));
                    $display("  DUT extended immediate=0x%08h (%0d)", cur_dut_imm, $signed(cur_dut_imm));
                end
                7'b1100011: begin
                    $display("  REF compare rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_src1);
                    $display("  DUT compare rs1=x%0d, value=0x%08h", cur_inst[19:15], cur_dut_src1);
                    $display("  REF compare rs2=x%0d, value=0x%08h", cur_inst[24:20], cur_src2);
                    $display("  DUT compare rs2=x%0d, value=0x%08h", cur_inst[24:20], cur_dut_src2);
                    $display("  REF extended branch immediate=0x%08h (%0d)", cur_imm, $signed(cur_imm));
                    $display("  DUT extended branch immediate=0x%08h (%0d)", cur_dut_imm, $signed(cur_dut_imm));
                end
                7'b0110111, 7'b0010111, 7'b1101111: begin
                    $display("  REF extended immediate=0x%08h (%0d)", cur_imm, $signed(cur_imm));
                    $display("  DUT extended immediate=0x%08h (%0d)", cur_dut_imm, $signed(cur_dut_imm));
                end
                default:
                    $display("  No source operand information for this opcode.");
            endcase
        end
    endtask

    task automatic report_common;
        input string error_type;
        begin
            $display("------------------------------------------------------------");
            $display("ERROR: %s", error_type);
//            $display("  Current instruction PC = 0x%08h", cur_pc);
            $display("  Current inst PC : REF = 0x%08h, DUT = 0x%08h", cur_pc, cur_dut_pc);
            $display("  Next PC         : REF = 0x%08h, DUT = 0x%08h", ref_pc, dut.pc);
//            $display("  Note: the post-state PCs are the next instruction's address;");
//            $display("        delta=4 is normal sequential flow, not a PC error.");
            $display("  Instruction binary = %032b", cur_inst);
            $display("  Instruction hex = 0x%08h", cur_inst);
            $display("  Assembly = %s", cur_assembly);
            print_source_operands();
        end
    endtask

    // Stop the whole simulation as soon as the error budget is exhausted.
    // $fatal alone is not enough: several simulators only print it (or require
    // a SystemVerilog language generation) and keep running, which makes the
    // run look like it merely "reported" the limit. $finish is legal Verilog
    // and is honoured everywhere, so it acts as the hard stop.
    task automatic stop_on_error_limit;
        begin
            $display("==================================================");
            $display("TEST FAILED: error limit reached (%0d/%0d errors), simulation stopped.",
                     errors, MAX_ERRORS);
            $display("  Stopped after %0d instructions; remaining checks were not run.",
                     executed_count);
            $display("  Instruction PC when the limit was hit = 0x%08h", cur_pc);
            $display("==== TEST FAILED ====");
            $display("==================================================");
            $fflush();
            $fatal(1);  // non-zero exit status for regression scripts
            $finish;    // hard stop, in case $fatal is ignored by the simulator
        end
    endtask

    task automatic count_error;
        begin
            errors = errors + 1;
            if (errors >= MAX_ERRORS)
                stop_on_error_limit();
        end
    endtask

    task automatic check_dmem_word;
        input integer word_index;
        input [31:0] byte_address;
        reg [31:0] dut_value;
        reg [31:0] ref_value;
        begin
            dut_value = dut.u_dmem.u_sram.sram[word_index];
            ref_value = ref_dmem[word_index];
            if (dut_value !== ref_value) begin
                report_common("Data memory mismatch");
                $display("  Data memory byte address = 0x%08h", byte_address);
                $display("  Data memory word index = 0x%04h", word_index);
                $display("  DUT memory value = 0x%08h", dut_value);
                $display("  REF memory value = 0x%08h", ref_value);
                count_error();
            end
        end
    endtask

    task automatic check_arch_state;
        integer reg_index;
        reg [31:0] expected_inst;
        begin
            if (dut.pc !== ref_pc) begin
                report_common("PC mismatch");
                $display("  Expected next PC = 0x%08h, DUT next PC = 0x%08h", ref_pc, dut.pc);
                count_error();
            end

            expected_inst = ref_imem[(ref_pc-start_pc) >> 2];
            if (dut.inst !== expected_inst) begin
                report_common("Fetched instruction mismatch");
                $display("  Fetch PC = 0x%08h", ref_pc);
                $display("  DUT fetched instruction = %032b (0x%08h)", dut.inst, dut.inst);
                $display("  REF fetched instruction = %032b (0x%08h)", expected_inst, expected_inst);
                count_error();
            end

            for (reg_index = 0; reg_index < 32; reg_index = reg_index + 1) begin
                if (dut.u_regfile.regs[reg_index] !== ref_regs[reg_index]) begin
                    report_common("Register mismatch");
                    $display("  Register = x%0d", reg_index);
                    $display("  DUT register value = 0x%08h", dut.u_regfile.regs[reg_index]);
                    $display("  REF register value = 0x%08h", ref_regs[reg_index]);
                    count_error();
                end
            end

            if (cur_mem_access)
                check_dmem_word(cur_mem_addr[15:2], cur_mem_addr);
        end
    endtask

    // One forward branch over a marker instruction. Both taken and not-taken
    // cases are generated with different operands and funct3 values.
    task automatic emit_branch_case;
        input [2:0] f3;
        input [4:0] rs2;
        input [4:0] rs1;
        integer branch_index;
        integer target_index;
        begin
            branch_index = program_count;
            emit(32'd0);
            emit(enc_i(12'd99, 5'd0, 3'b000, 5'd5, 7'b0010011));
            target_index = program_count;
            patch_b(branch_index, (target_index-branch_index)*4, rs2, rs1, f3);
            emit(enc_i(12'd1, 5'd5, 3'b000, 5'd5, 7'b0010011));
        end
    endtask

    task automatic generate_random_alu;
        input integer count;
        integer n;
        integer op;
        integer rd;
        integer rs1;
        integer rs2;
        reg [11:0] imm12;
        reg [6:0] f7;
        begin
            for (n = 0; n < count; n = n + 1) begin
                op = $urandom_range(18, 0);
                rd = $urandom_range(31, 0);
                rs1 = $urandom_range(31, 0);
                rs2 = $urandom_range(31, 0);
                imm12 = $urandom;
                case (op)
                    0:  emit(enc_r(7'b0000000, rs2, rs1, 3'b000, rd));
                    1:  emit(enc_r(7'b0100000, rs2, rs1, 3'b000, rd));
                    2:  emit(enc_r(7'b0000000, rs2, rs1, 3'b001, rd));
                    3:  emit(enc_r(7'b0000000, rs2, rs1, 3'b010, rd));
                    4:  emit(enc_r(7'b0000000, rs2, rs1, 3'b011, rd));
                    5:  emit(enc_r(7'b0000000, rs2, rs1, 3'b100, rd));
                    6:  emit(enc_r(7'b0000000, rs2, rs1, 3'b101, rd));
                    7:  emit(enc_r(7'b0100000, rs2, rs1, 3'b101, rd));
                    8:  emit(enc_r(7'b0000000, rs2, rs1, 3'b110, rd));
                    9:  emit(enc_r(7'b0000000, rs2, rs1, 3'b111, rd));
                    10: emit(enc_i(imm12, rs1, 3'b000, rd, 7'b0010011));
                    11: emit(enc_i(imm12, rs1, 3'b010, rd, 7'b0010011));
                    12: emit(enc_i(imm12, rs1, 3'b011, rd, 7'b0010011));
                    13: emit(enc_i(imm12, rs1, 3'b100, rd, 7'b0010011));
                    14: emit(enc_i(imm12, rs1, 3'b110, rd, 7'b0010011));
                    15: emit(enc_i(imm12, rs1, 3'b111, rd, 7'b0010011));
                    16: emit(enc_i({7'b0000000, imm12[4:0]}, rs1, 3'b001, rd, 7'b0010011));
                    17: emit(enc_i({7'b0000000, imm12[4:0]}, rs1, 3'b101, rd, 7'b0010011));
                    18: emit(enc_i({7'b0100000, imm12[4:0]}, rs1, 3'b101, rd, 7'b0010011));
                endcase
            end
        end
    endtask

    task automatic generate_random_memory;
        input integer count;
        integer n;
        integer op;
        integer rd_rs2;
        integer offset;
        reg [11:0] imm12;
        reg [2:0] f3;
        begin
            // x31 is a reserved base register (0x00001000) in this section.
            emit(enc_u(20'h00001, 5'd31, 7'b0110111));
            for (n = 0; n < count; n = n + 1) begin
                op = $urandom_range(7, 0);
                rd_rs2 = $urandom_range(30, 0); // Loads must not overwrite x31.
                case (op)
                    0, 1, 2: begin
                        offset = ($urandom_range(4095, 0) - 2048);
                        imm12 = offset[11:0];
                        case (op)
                            0: f3 = 3'b000; // sb
                            1: begin f3 = 3'b001; imm12[0] = 1'b0; end // sh
                            default: begin f3 = 3'b010; imm12[1:0] = 2'b00; end // sw
                        endcase
                        emit(enc_s(imm12, rd_rs2, 5'd31, f3));
                    end
                    default: begin
                        offset = ($urandom_range(4095, 0) - 2048);
                        imm12 = offset[11:0];
                        case (op)
                            3: f3 = 3'b000; // lb
                            4: begin f3 = 3'b001; imm12[0] = 1'b0; end // lh
                            5: begin f3 = 3'b010; imm12[1:0] = 2'b00; end // lw
                            6: f3 = 3'b100; // lbu
                            default: begin f3 = 3'b101; imm12[0] = 1'b0; end // lhu
                        endcase
                        emit(enc_i(imm12, 5'd31, f3, rd_rs2, 7'b0000011));
                    end
                endcase
            end
        end
    endtask

    task automatic generate_random_branches;
        input integer count;
        integer n;
        integer f3_choice;
        integer rs1;
        integer rs2;
        integer rd;
        reg [2:0] f3;
        begin
            for (n = 0; n < count; n = n + 1) begin
                f3_choice = $urandom_range(5, 0);
                case (f3_choice)
                    0: f3 = 3'b000;
                    1: f3 = 3'b001;
                    2: f3 = 3'b100;
                    3: f3 = 3'b101;
                    4: f3 = 3'b110;
                    default: f3 = 3'b111;
                endcase
                rs1 = $urandom_range(31, 0);
                rs2 = $urandom_range(31, 0);
                rd = $urandom_range(31, 0);
                emit(enc_b(13'd8, rs2, rs1, f3));
                emit(enc_i($urandom, 5'd0, 3'b000, rd, 7'b0010011));
            end
        end
    endtask


    task automatic build_program;
        integer index;
        integer target;
        integer label_pc;
        integer n;
        begin
            program_count = 0;
            for (n = 0; n < MEM_WORDS; n = n + 1)
                program_mem[n] = 32'd0;

            // Boundary register values: 0, 1, INT_MAX, INT_MIN and UINT_MAX.
            emit(enc_i(12'd0,   5'd0, 3'b000, 5'd1,  7'b0010011));
            emit(enc_i(-12'd1,  5'd1, 3'b000, 5'd1,  7'b0010011)); // x1=ffffffff
            emit(enc_u(20'h80000, 5'd2, 7'b0110111));               // x2=80000000
            emit(enc_u(20'h7ffff, 5'd3, 7'b0110111));
            emit(enc_i(12'h7ff, 5'd3, 3'b000, 5'd3,  7'b0010011)); // x3=7fffffff
            emit(enc_i(12'd1,   5'd0, 3'b000, 5'd4,  7'b0010011)); // x4=1

            // Arithmetic overflow and signed/unsigned comparison boundaries.
            emit(enc_r(7'b0000000, 5'd4, 5'd3, 3'b000, 5'd5)); // INT_MAX+1
            emit(enc_r(7'b0100000, 5'd4, 5'd2, 3'b000, 5'd6)); // INT_MIN-1
            emit(enc_r(7'b0000000, 5'd1, 5'd1, 3'b000, 5'd7)); // ffffffff+ffffffff
            emit(enc_r(7'b0100000, 5'd3, 5'd3, 3'b000, 5'd8)); // equal subtraction
            emit(enc_r(7'b0000000, 5'd3, 5'd2, 3'b010, 5'd9)); // slt INT_MIN,INT_MAX
            emit(enc_r(7'b0000000, 5'd2, 5'd3, 3'b010, 5'd10));
            emit(enc_r(7'b0000000, 5'd4, 5'd1, 3'b011, 5'd11)); // sltu UINT_MAX,1
            emit(enc_r(7'b0000000, 5'd1, 5'd0, 3'b011, 5'd12)); // sltu 0,UINT_MAX

            // Requested special cases: xori -1 and sltiu 1.
            emit(enc_i(-12'd1,  5'd1, 3'b100, 5'd7,  7'b0010011)); // xori ffffffff,-1
            emit(enc_i(-12'd1,  5'd0, 3'b100, 5'd8,  7'b0010011)); // xori x0,-1
            emit(enc_i(12'd0,   5'd1, 3'b111, 5'd9,  7'b0010011)); // andi 0
            emit(enc_i(-12'd1,  5'd0, 3'b110, 5'd10, 7'b0010011)); // ori -1
            emit(enc_i(12'd1,   5'd2, 3'b010, 5'd11, 7'b0010011)); // slti INT_MIN,1
            emit(enc_i(-12'd1,  5'd3, 3'b010, 5'd12, 7'b0010011));
            emit(enc_i(12'd1,   5'd0, 3'b011, 5'd13, 7'b0010011)); // sltiu 0,1
            emit(enc_i(12'd1,   5'd1, 3'b011, 5'd14, 7'b0010011)); // sltiu UINT_MAX,1
            emit(enc_i(-12'd1,  5'd1, 3'b011, 5'd15, 7'b0010011)); // equal unsigned
            emit(enc_i(12'h7ff, 5'd0, 3'b000, 5'd16, 7'b0010011)); // max I immediate
            emit(enc_i(12'h800, 5'd0, 3'b000, 5'd17, 7'b0010011)); // min I immediate

            // Immediate shifts: shamt 0, 1, 30 and 31.
            emit(enc_i({7'b0000000, 5'd31}, 5'd4, 3'b001, 5'd18, 7'b0010011));
            emit(enc_i({7'b0000000, 5'd31}, 5'd18,3'b101, 5'd19, 7'b0010011));
            emit(enc_i({7'b0100000, 5'd31}, 5'd2, 3'b101, 5'd20, 7'b0010011));
            emit(enc_i({7'b0000000, 5'd0},  5'd2, 3'b101, 5'd21, 7'b0010011));
            emit(enc_i({7'b0000000, 5'd30}, 5'd4, 3'b001, 5'd22, 7'b0010011));

            // Register shift amounts above 31 must use only rs2[4:0].
            emit(enc_i(12'd32,  5'd0, 3'b000, 5'd23, 7'b0010011));
            emit(enc_r(7'b0000000, 5'd23, 5'd4, 3'b001, 5'd24)); // shift 32 -> 0
            emit(enc_i(12'd33,  5'd0, 3'b000, 5'd23, 7'b0010011));
            emit(enc_r(7'b0000000, 5'd23, 5'd4, 3'b001, 5'd25)); // shift 33 -> 1
            emit(enc_i(12'd63,  5'd0, 3'b000, 5'd23, 7'b0010011));
            emit(enc_r(7'b0100000, 5'd23, 5'd2, 3'b101, 5'd26)); // sra 63 -> 31
            emit(enc_r(7'b0000000, 5'd23, 5'd2, 3'b101, 5'd27)); // srl 63 -> 31
            emit(enc_i(12'd255, 5'd0, 3'b000, 5'd23, 7'b0010011));
            emit(enc_r(7'b0000000, 5'd23, 5'd4, 3'b001, 5'd28)); // shift 255 -> 31

            // x0 as a source and as a destination.
            emit(enc_i(12'd5,  5'd0, 3'b000, 5'd24, 7'b0010011));
            emit(enc_r(7'b0000000, 5'd0, 5'd0, 3'b000, 5'd25));
            emit(enc_i(-12'd1, 5'd0, 3'b000, 5'd0,  7'b0010011));
            emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd0));
            emit(enc_u(20'hfffff, 5'd0, 7'b0110111));
            emit(enc_u(20'h00001, 5'd0, 7'b0010111));

            // Directed subword loads/stores and all byte lanes.
            emit(enc_u(20'h80ff7, 5'd27, 7'b0110111));
            emit(enc_i(12'h701, 5'd27, 3'b000, 5'd27, 7'b0010011));
            emit(enc_s(12'd0, 5'd27, 5'd0, 3'b010));             // sw pattern,0(x0)
            emit(enc_i(12'd0, 5'd0, 3'b000, 5'd5, 7'b0000011)); // lb offset 0
            emit(enc_i(12'd1, 5'd0, 3'b000, 5'd6, 7'b0000011)); // lb offset 1
            emit(enc_i(12'd2, 5'd0, 3'b100, 5'd7, 7'b0000011)); // lbu offset 2
            emit(enc_i(12'd3, 5'd0, 3'b000, 5'd8, 7'b0000011)); // lb offset 3
            emit(enc_i(12'd0, 5'd0, 3'b001, 5'd9, 7'b0000011)); // lh
            emit(enc_i(12'd2, 5'd0, 3'b101, 5'd10,7'b0000011)); // lhu
            emit(enc_i(12'd0, 5'd0, 3'b010, 5'd0, 7'b0000011)); // lw x0
            emit(enc_s(12'd4, 5'd2, 5'd0, 3'b010));
            emit(enc_i(12'd4, 5'd0, 3'b001, 5'd11,7'b0000011)); // lh 8000
            emit(enc_i(12'd6, 5'd0, 3'b101, 5'd12,7'b0000011)); // lhu 8000
            emit(enc_s(12'd8, 5'd4, 5'd0, 3'b000));              // sb 1,8(x0)
            emit(enc_s(12'd9, 5'd1, 5'd0, 3'b000));              // sb ff,9(x0)
            emit(enc_s(12'd10,5'd3, 5'd0, 3'b001));              // sh 7fff,10(x0)
            emit(enc_i(12'd8, 5'd0, 3'b010, 5'd13,7'b0000011));
            emit(enc_s(12'd12,5'd1, 5'd0, 3'b001));              // sh ffff,12(x0)
            emit(enc_i(12'd12,5'd0, 3'b101, 5'd14,7'b0000011));

            // Highest byte and word addresses in the 64 KiB data memory.
            emit(enc_u(20'h00010, 5'd28, 7'b0110111));
            emit(enc_i(-12'd4, 5'd28,3'b000, 5'd28,7'b0010011)); // fffc
            emit(enc_s(12'd0, 5'd3, 5'd28,3'b010));
            emit(enc_i(12'd0, 5'd28,3'b010, 5'd15,7'b0000011));
            emit(enc_u(20'h00010, 5'd29, 7'b0110111));
            emit(enc_i(-12'd1, 5'd29,3'b000, 5'd29,7'b0010011)); // ffff
            emit(enc_s(12'd0, 5'd1, 5'd29,3'b000));
            emit(enc_i(12'd0, 5'd29,3'b100, 5'd16,7'b0000011));

            // Every branch: taken and not taken.
            emit_branch_case(3'b000, 5'd0, 5'd0); // beq taken
            emit_branch_case(3'b000, 5'd0, 5'd1); // beq not taken
            emit_branch_case(3'b001, 5'd0, 5'd1); // bne taken
            emit_branch_case(3'b001, 5'd0, 5'd0); // bne not taken
            emit_branch_case(3'b100, 5'd3, 5'd2); // blt taken
            emit_branch_case(3'b100, 5'd2, 5'd3); // blt not taken
            emit_branch_case(3'b101, 5'd2, 5'd3); // bge taken
            emit_branch_case(3'b101, 5'd3, 5'd2); // bge not taken
            emit_branch_case(3'b110, 5'd1, 5'd0); // bltu taken
            emit_branch_case(3'b110, 5'd0, 5'd1); // bltu not taken
            emit_branch_case(3'b111, 5'd0, 5'd1); // bgeu taken
            emit_branch_case(3'b111, 5'd1, 5'd0); // bgeu not taken

            // Backward branch loop: three iterations, then exit.
            emit(enc_i(12'd3, 5'd0, 3'b000, 5'd24,7'b0010011));
            label_pc = program_count;
            emit(enc_i(-12'd1,5'd24,3'b000, 5'd24,7'b0010011));
            emit(enc_b((label_pc-program_count)*4, 5'd0, 5'd24,3'b001));

            // Largest aligned positive B-type offset: +4092.
            index = program_count;
            emit(32'd0);
            for (n = 0; n < 1022; n = n + 1)
                emit(enc_i(12'd0, 5'd0, 3'b000, 5'd0, 7'b0010011));
            target = program_count;
            patch_b(index, (target-index)*4, 5'd0, 5'd0, 3'b000);
            emit(enc_i(12'd1, 5'd25,3'b000, 5'd25,7'b0010011));

            // Minimum B-type offset: -4096, taken once and then not taken.
            emit(enc_i(12'd2, 5'd0, 3'b000, 5'd20,7'b0010011));
            label_pc = program_count;
            emit(enc_i(-12'd1,5'd20,3'b000, 5'd20,7'b0010011));
            for (n = 0; n < 1023; n = n + 1)
                emit(enc_i(12'd0, 5'd0, 3'b000, 5'd0, 7'b0010011));
            index = program_count;
            emit(enc_b((label_pc-index)*4, 5'd0, 5'd20,3'b001));

            // JAL subroutine call and JALR return. Link values are checked every cycle.
            index = program_count;                     // call
            emit(32'd0);
            emit(enc_i(12'd7, 5'd0, 3'b000, 5'd7, 7'b0010011)); // return address
            target = program_count;                    // jump over subroutine
            emit(32'd0);
            label_pc = program_count;                  // subroutine
            emit(enc_i(12'd6, 5'd0, 3'b000, 5'd6, 7'b0010011));
            emit(enc_i(12'd0, 5'd1, 3'b000, 5'd0, 7'b1100111)); // jalr x0,0(x1)
            patch_j(index, (label_pc-index)*4, 5'd1);
            patch_j(target, (program_count-target)*4, 5'd0);

            // JALR must clear target bit 0. auipc supplies an absolute target base.
            emit(enc_u(20'h00000, 5'd8, 7'b0010111));  // A: x8=A
            emit(enc_i(12'd17, 5'd8, 3'b000, 5'd8, 7'b0010011)); // A+17 -> bit0=1
            emit(enc_i(12'd0, 5'd8, 3'b000, 5'd9, 7'b1100111)); // target A+16
            emit(enc_i(12'd88,5'd0, 3'b000, 5'd5, 7'b0010011)); // skipped
            emit(enc_i(12'd9, 5'd0, 3'b000, 5'd10,7'b0010011));

            // JALR rd==rs1: target must use the old rs1 value.
            emit(enc_u(20'h00000, 5'd10,7'b0010111));  // B: x10=B
            emit(enc_i(12'd16, 5'd10,3'b000, 5'd10,7'b0010011)); // old x10=B+16
            emit(enc_i(12'd0, 5'd10,3'b000, 5'd10,7'b1100111)); // link=B+12
            emit(enc_i(12'd77,5'd0, 3'b000, 5'd5, 7'b0010011)); // skipped
            emit(enc_i(12'd11,5'd0, 3'b000, 5'd11,7'b0010011));

            // JALR with a negative immediate: (A+20)-4=A+16.
            emit(enc_u(20'h00000, 5'd12,7'b0010111));
            emit(enc_i(12'd20, 5'd12,3'b000, 5'd12,7'b0010011));
            emit(enc_i(-12'd4, 5'd12,3'b000, 5'd13,7'b1100111));
            emit(enc_i(12'd66,5'd0, 3'b000, 5'd5, 7'b0010011)); // skipped
            emit(enc_i(12'd13,5'd0, 3'b000, 5'd14,7'b0010011));

            // Backward JAL subroutine call, preceded by a forward jump to the call site.
            index = program_count;
            emit(32'd0);
            label_pc = program_count;                  // earlier subroutine
            emit(enc_i(12'd12,5'd0, 3'b000, 5'd6, 7'b0010011));
            emit(enc_i(12'd0, 5'd1, 3'b000, 5'd0, 7'b1100111));
            target = program_count;                    // backward call site
            emit(32'd0);
            emit(enc_i(12'd14,5'd0, 3'b000, 5'd7, 7'b0010011)); // return address
            patch_j(index, (target-index)*4, 5'd0);
            patch_j(target, (label_pc-target)*4, 5'd1);

            // Random arithmetic, branch and memory regression.
            generate_random_alu(RANDOM_ALU_COUNT);
            generate_random_branches(RANDOM_BRANCH_COUNT);
            generate_random_memory(RANDOM_MEM_COUNT);

            end_pc = program_count * 4;
            emit(END_INSTRUCTION);
        end
    endtask

    initial begin : run_test
        integer done;

        clk = 1'b0;
        reset = 1'b1;

        // This is the byte address of imem.hex entry 0. Change it together
        // with the program's link/load address when using another start address.
        start_pc = 32'h00000000;
        errors = 0;
        executed_count = 0;
        done = 0;

        $display("INFO: Loading instructions from imem.hex.");
        $display("INFO: Loading initial data from dmem.hex.");
        $display("INFO: imem.hex entry 0 maps to start_pc = 0x%08h.", start_pc);

        ref_pc = start_pc;
        for (i = 0; i < 32; i = i + 1)
            ref_regs[i] = 32'd0;
        for (i = 0; i < MEM_WORDS; i = i + 1)
            ref_imem[i] = 32'd0;
        $readmemh("imem.hex", ref_imem);
        $readmemh("dmem.hex", ref_dmem);
        $readmemh("imem.hex", dut.u_imem.u_sram.sram);
        $readmemh("dmem.hex", dut.u_dmem.u_sram.sram);

        // Locate the terminating jal x0,0 in the file and translate its file
        // index to a byte address using the same start_pc convention as the DUT.
        end_pc = -1;
        program_count = 0;
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            if (ref_imem[i] !== 32'd0)
                program_count = i + 1;
            if (!done && (ref_imem[i] == END_INSTRUCTION)) begin
                end_pc = start_pc + i*4;
                done = 1;
            end
        end
        if (!done) begin
            $display("ERROR: Cannot find the terminating jal x0,0 in imem.hex.");
            $fatal(1);
            $finish;
        end
        done = 0;
        $display("INFO: Program contains %0d instructions. End PC = 0x%08h.",
                 program_count, end_pc);

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;
        $display("INFO: Starting per-instruction comparison.");

        // The error-budget term is a belt-and-braces guard: even if the
        // simulator ignores the stop request, no further instruction is run
        // or compared once MAX_ERRORS has been reached.
        while (!done && (executed_count < MAX_INSTRUCTIONS) && (errors < MAX_ERRORS)) begin
            cur_pc = ref_pc;
            cur_inst = ref_imem[(cur_pc-start_pc) >> 2];
            cur_assembly = disassemble(cur_inst);

            // Capture DUT source operands before the active clock edge. Later
            // register writes must not change the values used by this instruction.
            cur_dut_src1 = dut.read_data_1;
            cur_dut_src2 = dut.read_data_2;
            cur_dut_imm  = dut.imm;
            cur_dut_pc   = dut.pc;
            ref_step();

            @(posedge clk);
            #1;
            executed_count = executed_count + 1;
            check_arch_state();

            if ((cur_pc == end_pc) && (cur_inst == END_INSTRUCTION))
                done = 1; // The terminating JAL has also been checked.
            else
                @(negedge clk);
        end

        if (executed_count >= MAX_INSTRUCTIONS) begin
            report_common("Instruction count limit reached");
            count_error();
        end

        // Final exhaustive data-memory comparison catches untouched-word errors.
        // Skipped once the error budget is spent: there is nothing left to report.
        if (errors < MAX_ERRORS) begin
            for (i = 0; i < MEM_WORDS; i = i + 1)
                check_dmem_word(i, i*4);
        end

        $display("==================================================");
        if (errors >= MAX_ERRORS) begin
            $display("TEST FAILED: stopped at the %0d-error limit after %0d instructions.",
                     MAX_ERRORS, executed_count);
            $display("==== TEST FAILED ====");
        end
        else if (errors == 0) begin
            $display("TEST PASSED: %0d instructions checked.", executed_count);
            $display("TEST PASSED: PC, instructions, x0-x31 and data memory match the reference model.");
            $display("==== TEST PASSED ====");
        end
        else begin
            $display("TEST FAILED: %0d error(s) detected within the %0d-error budget.",
                     errors, MAX_ERRORS);
            $display("==== TEST FAILED ====");
        end
        $display("==================================================");

        $finish;
    end

endmodule
