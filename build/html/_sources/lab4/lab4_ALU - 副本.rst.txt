实验四 算术逻辑单元 ALU 设计
========================


本实验中，我们将完成算术逻辑单元 (ALU) 的设计与仿真，为后续的处理器设计奠定基础。


1. ALU 功能描述
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

我们要设计一个算术逻辑单元 (ALU)，输入输出如图所示：

.. figure:: ./pics/ALU.jpg
   :alt: ALU
   :align: center
   :scale: 20

A 和 B 是两个 32 位的输入操作数，Result 是 32 位的运算结果。具体做什么运算由 6 位的 ALUControl 决定，如表格所示：

.. figure:: ./pics/ALUoperation.png
   :alt: ALUOperation
   :align: center
   :scale: 18


此外，ALU 还需要对比两个输入操作数的数值大小，并输出相应的标志位，具体如下表：

.. figure:: ./pics/flagbits.png
   :alt: flagbits
   :align: center
   :scale: 18



2. 实验内容
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
用减法实现大小值判断
-------------------------------
加、减、与、或、异或、移位操作的 verilog 实现比较简单，这里着重讨论如何基于减法的结果完成两个操作数的大小值判断。

减法运算在硬件上是可以基于加法运算实现的，如图。我们可以根据减法的结果以及两个输入操作数的最高位，来判断数值大小。

.. figure:: ./pics/subtractor.png
   :alt: subtractor
   :align: center
   :scale: 10


.. admonition:: 必做内容1：证明判断数值大小的逻辑
   :class: mytodo

   已知输入操作数 A、B、减法运算的输出进位 cout，判断 ``A < B`` 的逻辑为：

   * 对于无符号数，当 ``cout = 0`` 时， ``A < B``;
   * 对于有符号数，当 ``A[31] ^ B[31] ^ cout = 0`` 时， ``A < B``; 

   请证明以上逻辑是正确的。


.. admonition:: 必做内容2：Verilog 代码设计
   :class: mytodo

   根据功能描述完成 ALU verilog 代码的设计。注意 **A \>= B** 的逻辑可以由 **A \< B** 的逻辑取反推出。

    .. code-block:: v
        :caption: ALU 代码框架
        :linenos:

         module ALU(
            input wire [31:0] input_A,
            input wire [31:0] input_B,
            input wire [5:0]  ALUctrl,
            output reg [31:0] result,
            output wire zero,
            output wire lt,
            output wire ltu,
            output wire ge,
            output wire geu
            );

            wire c_out;

            // Your codes should start from here.
            // ......
            // End of your codes.

         endmodule


.. admonition:: 必做内容3：testbench 仿真
   :class: mytodo

   这里提供 testbench 文件：:download:`tb_ALU.v (点击下载) <Lab4_Report_26Fall.docx>` 。完成 ALU 模块的测试，并对 “所有 case 通过测试” 的界面进行截图。


   .. code-block:: v
      :caption: 交通灯fsm top
      :emphasize-lines: 10, 17
      :linenos:

      module light_top (
         clk     
         ,reset  
         ,led_out 
         ,code   
         ,cs_o  
      );

         input   clk, reset;
         output  led_out;        // out for 24 LED
         output  code, cs_o;

         wire    clk, reset;
         wire [23:0] led_out;
         wire [7:0]  code, cs_o;

         wire [31:0] seg_out;   // out for seg
         wire [2:0]  light_east_west_through, light_east_west_leftturn, 
                     light_south_north_through, light_south_north_leftturn; 
         wire [7:0]  count_east_west_through, count_east_west_leftturn, 
                     count_south_north_through, count_south_north_leftturn;

         trafficlight_fsm u_trafficlight_fsm(
            .clk                            (clk)    
            ,.reset                         (reset)
            ,.light_east_west_through       (light_east_west_through)
            ,.light_east_west_leftturn      (light_east_west_leftturn)
            ,.light_south_north_through     (light_south_north_through)
            ,.light_south_north_leftturn    (light_south_north_leftturn)
            ,.count_east_west_through       (count_east_west_through)
            ,.count_east_west_leftturn      (count_east_west_leftturn)
            ,.count_south_north_through     (count_south_north_through)
            ,.count_south_north_leftturn    (count_south_north_leftturn)
         );
         


      endmodule



3. 报告提交
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

本次实验需要提交：

   * 实验报告：:download:`下载实验报告模板 <Lab4_Report_26Fall.docx>` 
   * ``.v`` 文件压缩包：包含设计文件和仿真文件

两项一同扫码提交（支持从微信聊天记录上传）。

.. raw:: html

   <p>Deadline ：<strong style="color: #d32f2f;">2026-11-01 23:59:59 </strong>。</p>

.. figure:: ./pics/FCMA203_26Fall_Lab4QR.png
   :alt: QRcode
   :scale: 50
   :align: center
