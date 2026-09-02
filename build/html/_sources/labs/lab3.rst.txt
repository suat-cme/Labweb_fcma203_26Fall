实验三 加减法器设计
==========================================

加减法器
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

如果参与运算的操作数都是补码，那么加法器是可以同时实现加法和减法操作的。
``A - B = A + (-B)`` ，因此我们对B的补码进行取反加一操作，就能得到 -B，
再让 A 与 -B 经过加法器相加，便完成了 A - B 的操作。

在前面的异或门实验中，我们得知， **可以通过异或门可控取反操作数，加一操作可以
输入到进位输入端口** ，这样就能完成取反加一的操作了。因此我们稍加修改，即可让
加法器也能实现减法操作，如下图所示。

.. figure:: ../picture/lab3/adder.png
   :alt: adder
   :align: center

其中 Sub 为1代表做减法运算，Sub 为0代表做加法运算。

.. raw:: html

   <div class="admonition mytodo">
      <p class="admonition-title">加法器的 RTL 实现</p >
      <p>使用实验二中的 cla_4bit 模块搭建层次化的 cla_8bit ，并仿真验证。
      然后按照上图的方式搭建能够实现减法操作的电路，完成最终的加法器设计并仿真验证。</p>
   </div>


输出加法器结果
----------------------------------------

我们提供了一些源代码，能够让你的加法器能够在 FPGA 上输入输出。加法器的输入有 8bit 的 a 和 b，以及 sub 信号，因此需要
17个输入，我们的 FPGA 上拥有 24 个用户拨码开关。

.. figure:: ../picture/lab3/minisys.png
   :alt: minisys
   :align: center

我们计划使用 7段数码管 显示你的加法器结果，拨码开关作为你的加法器二进制输入，每一个开关代表一位二进制数。
我们提供了 7段数码管 的控制电路：seg_driver 模块，你需要做的是将你的加法器结果输出到 seg_driver 模块的 data 端口，
data 端口是32位宽的端口，因为有 8个 7段数码管，因此可以16进制数显示32位宽的二进制数。

.. code-block:: v
   :caption: 顶层模块代码框架
   :emphasize-lines: 11, 23, 27
   :linenos:

    module top (
        clk     
        ,a      
        ,b      
        ,ctrl_addsub
        ,reset  
        ,code   
        ,cs_o  
    );

    parameter n = 8;

    input   wire            clk;    // 100 Mhz System Clock
    input   wire    [n-1:0] a, b;
    input   wire            ctrl_addsub;
    input   wire            reset;
    output  wire    [7:0]   code;
    output  wire    [7:0]   cs_o;

    wire    [n-1:0] sum;
    wire            cout;

    adder_sub_4bit u_adder_sub_4bit(a[3:0], b[3:0], sum[3:0], cout, ctrl_addsub);  // change to instant of your add/sub module

    seg_driver u_seg_driver(
        .clk     (clk)
        ,.data   ({27'd0, cout, sum})   
        ,.reset  (reset)
        ,.code   (code)
        ,.cs_o   (cs_o)
    );

    endmodule


.. raw:: html

   <div class="admonition mytodo">
      <p class="admonition-title">加法器连接7段数码管</p >
      <p>我们只需要修改第27行代码的 data 端口连接上你的加法器输出，同时注意位宽需要匹配。
      完成 RTL 代码的修改。这样我们提供的7段数码管电路就会将你的二进制数转换为16进制数，
      并最终在 FPGA 的7段数码管上显示出来。</p>
   </div>


逻辑综合 Logic Synthesis
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

我们都已经上手写过一些 Verilog 代码了，本次实验我们会使用修改并验证过的代码，在 FPGA 上运行我们设计的加减法器。

那么 FPGA 是什么呢？ FPGA (Field-Programmable Gate Array) 可以翻译为现场可编程逻辑门阵列。
我们写好的 Verilog 可以转换为我们熟悉的门电路，我们可以按照这些门电路的连线关系生产成专用的集成电路，
也就是 ASIC (Application-Specific Integrated Circuit) 。而 FPGA 则完全不同，它是一种可编程逻辑器件(PLD, Programmable Logic Device)，
允许用户在硬件层面上根据需求进行编程，那么具体功能是怎么实现的呢？

LUT (Look-Up Table) 查找表结构可以通过编程定义功能，逻辑功能可以通过查表来实现。

.. figure:: ../picture/lab3/lut_xor.png
   :alt: lut_xor
   :align: center

我们通过一个简易的 **2输入查找表** 例子学习如何实现2输入门电路等功能。查找表可以通过 **多路选通器** 实现。
多路选通器的输入通过我们编程配置，也就是将真值表填入多路选择信号，即可实现与或非、异或等门电路的功能。如上图所示。
如果我要完成 ``assign y = (a & b) | c;`` 的逻辑功能，同理可以使用一个3输入查找表来实现，这些配置信息保存在存储器中。

Xilinx 的 FPGA 查找表一般设计为6个输入，那么就需要64bit的存储器来存储6个变量所有的可能组合，这个查找表也可以作为两个5输入的查找表使用，
也可以拆分成更小的查找表来使用。因此这些 6输入查找表 (LUT6) 可以完成复杂的逻辑功能。

.. figure:: ../picture/lab3/CLBLM.png
   :alt: CLBLM
   :align: center

上图是我们使用的 ``xc7a100tfgg484`` 芯片中的真实的一个可配置逻辑块 (CLB) 的结构，里面又分为两种SLICE ：SLICEL 与 SLICEM，它们的 LUT 部分不一样，其余部分一样。
SLICEL 的 LUT 主要用于 Logic 逻辑功能，而 SLICEM 的 LUT 主要用于 Memory 结构，可以用于分布式 RAM 或者 移位寄存器等。
此外还有专用电路部分，多路选通器、加法器以及寄存器。

综合是把 HDL 代码经过一系列步骤，最终映射为电路的过程。Vivado 综合器可以将可综合的语法转换为 LUT、多路选通器、加法器、寄存器、存储器等 FPGA 
内部的基本电路。综合完成之后，就能得到网表文件 (netlist)，用于描述电路单元之间连接关系。

.. raw:: html

   <div class="admonition mycomment">
      <p class="admonition-title">ASIC设计与FPGA的区别</p >
      <p>ASIC 专用集成电路的逻辑功能不需要能够编程配置，因此综合器可以直接将 HDL 转换成基础的门电路，
      以及一些常见的单元，寄存器、锁存器等。这些基础电路库一般由芯片制造厂商提供，比如TSMC台积电。
      我们把这些基础电路库称为<strong>Std Cell 标准单元库</strong>。ASIC 的电路映射更灵活，
      门的大小与位置都可以灵活调整，更好布局布线。而 FPGA 的灵活程度没有那么高，通常布线延迟占大头。
      以 Sifive U500 4核SoC处理器为例，在采用相似的工艺情况下，ASIC 设计的 Sifive U500 宣称运行频率高达 1.5Ghz，
      而同样是28nm的 Xilinx FPGA VC707 上综合的 Sifive U500 最高只能以 200Mhz 频率运行。</p>
   </div>


在 Vivado 中，设计文件中被 ``Set as Top`` 的文件用于流程中的设计实现，仿真文件中被 ``Set as Top`` 的文件用于运行仿真。我们可以在 ``Source`` 栏对你想要的顶层模块右键设置其为顶层。
将仿真完成的文件进行综合，在 ``Flow Navigator`` 中点击 ``Run Synthesis`` 开始综合，综合完成之后会弹窗，可以直接关闭弹窗。

综合之后的设计可以打开 ``Open Synthesis Design`` 栏，里面有很多内容，我们暂时只关心 ``Schematic`` 电路原理图部分。
点击打开电路原理图，我们可以看到 HDL 转换之后的电路原理图，如下图所示。

.. figure:: ../picture/lab3/Schematic.png
   :alt: Schematic
   :align: center

点击模块左上角的加号可以展开模块内部的细节，仔细查看可以发现有 LUT2、LUT5、LUT6、CARRY4、FDCE 等熟悉的基础电路单元。
以及输入输出部分的很多 BUF 缓冲器等。Vivado 综合器将你写的 Verilog 代码变成了 FPGA 器件上面的基础电路单元，
以及它们的连线关系，在后续的步骤会将这些基础电路单元映射到 FPGA 芯片上某些真实的电路单元。

实现 Implementation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

直接点击 ``Run Implementation`` 即可实现设计，其大致包含几个步骤：

- opt_design 逻辑优化，优化你的设计，使网表更利于时序与布线。
- place_design 布局，将电路原理图映射到 FPGA 电路单元。
- route_design 布线，将这些电路单元通过数据通路连接起来。

在完成实现之后，会弹窗，可以直接关闭弹窗。
实现之后的设计可以打开 ``Open Implemented Design`` 栏，右侧会显示芯片的版图，
其中高亮的部分是我们实际使用的电路单元，可以放大仔细查看我们使用的具体的电路单元，
会发现之前电路原理图中的熟悉的单元名字。

.. figure:: ../picture/lab3/Layout.png
   :alt: Layout
   :align: center

管脚绑定 I/O Planning
----------------------------------------

在这个界面，我们可以将顶层设计模块中的输入输出端口与芯片的真实的管脚进行绑定。
有两种方法，一种是添加设计约束文件进行绑定，另一种是使用图形化界面进行绑定。
当然我认为第一种更便捷，不过推荐你两种方法都尝试一次。

方法一 添加设计约束文件
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

我们以复位按键信号的管脚绑定为例 (时钟信号以后再讲) ，以下是约束语句的含义。

.. code-block::
   :caption: adder.xdc片段
   :linenos:

    set_property PACKAGE_PIN P20 [get_ports reset]
    set_property IOSTANDARD LVCMOS33 [get_ports reset]


第一行是指定顶层端口 reset 输入信号与 FPGA 封装管脚 P20 相连，通过 FPGA 硬件手册我们知道，
P20 管脚与 S6 按键电路相连，可以用来作为复位信号输入。

第二行是指定 reset 端口的 I/O 电气标准设置为 LVCMOS33，这个是依据 S6 按键电路的高电平电压是3.3V，
否则电气标准不匹配可能会导致功能失效，甚至对芯片、硬件电路等造成损伤。

我们给出了一个设计约束文件的模板，主要是本次实验有部分电路是我们提供的，用于演示加减法结果。
因此你可以对拨码输入等按键进行更改，所有的电路以及管脚信息都在 FPGA 硬件手册中。

以下图为例，展示了 S6 按键的电路信息。

.. figure:: ../picture/lab3/S6.png
   :alt: S6
   :align: center

S6 按键被我作为 ``reset`` 复位信号输入到 FPGA 内部，当按下 S6 按键时，P20 管脚连接 3.3V 电平，输入为逻辑1；
当松开 S6 时，P20 接地，输入为逻辑0。

完成设计如约束文件的编写后，在添加源文件的地方选择 ``Add Deisgn Constraints`` 添加约束文件，Vivado 约束文件的后缀名为 ``.xdc`` ，
代表 Xilinx Deisgn Constraints ，约束文件添加后，可以右键点击约束文件，选择 ``Set as Target Constraint File``，确保该文件作为目标的
约束文件，文件名后面会出现 **(target)** ，标明这个约束文件作为目标约束文件。

.. figure:: ../picture/lab3/Constraints.png
   :alt: Constraints
   :align: center

方法二 使用图形化绑定管脚
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

在 ``Implemented Design`` 界面，也可以使用图形化的方式绑定管脚。

.. figure:: ../picture/lab3/io_planning.png
   :alt: io_planning
   :align: center

在下方的 ``Package Pin`` 和 ``I/O Std`` 中填入正确的信息。 
本次实验的最好是按照我们给的设计约束文件进行管脚绑定，当然你能够根据 FPGA 硬件手册自由修改按键绑定也没问题。

完成图形化的管脚绑定后，快捷键 ``ctrl + s`` 保存设计约束文件，你可以存放在指定的位置，然后查看，你会发现其实通过这种方式生成的
设计约束文件与我们给的设计约束文件没有区别，因此你可以手动编写设计约束文件，最简单的办法就是使用模板进行修改。

完成设计约束文件后，由于更新了源文件，需要重新进行综合与实现。再次实现完成之后，观察版图，你会发现这次使用的电路单元应该与之前没有约束文件时是不同的。
因为我们有了管脚约束之后，会重新布局布线，与 FPGA 真实的封装管脚相连。

写入比特流 Open Hardware Manager
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

完成实现之后，点击 ``Generate Bitstream`` 会生成最后需要写入 FPGA 编程的文件，称之为比特流文件。
如果在这一步报错，很可能是设计约束文件有错误，需要检查错误信息，设计约束文件是否错误。

.. raw:: html

   <div class="admonition mycaution">
      <p class="admonition-title">驱动安装</p >
      <p>请仔细检查你的驱动程序是否安装，如果没有安装，请按照 Vivado 安装教程安装驱动程序，否则电脑无法检测到 FPGA ，无法对 FPGA 进行编程。</p>
   </div>


将 FPGA 的 USB 接口与 电脑相连，打开电源开关， FPGA 将通电并发光，如下图所示。

.. figure:: ../picture/lab3/poweron.png
   :alt: poweron
   :align: center

最后点击 ``Open Hardware Manager`` ，再点击 ``Open Target`` ，点击 ``Auto Connect`` 自动连接设备。

.. figure:: ../picture/lab3/hardware_manager.png
   :alt: hardware_manager
   :align: center


如上图所示，成功连接 FPGA 后会在 ``Hardware`` 栏显示 FPGA 的状态和信息。
点击编程设备，然后直接点击编程，等待编程进度条完毕。

点击 ``Program Device`` 后默认会自动选择好比特流文件，如下图所示。
如果你不小心删除了，可以手动选取生成的比特流文件，在工程目录的 ``<工程名>.runs//impl_1/<顶层模块名>.bit`` 。

编程完成 FPGA 之后，即可尝试波动用户拨码开关，观察 7段数码管 的结果。

.. raw:: html

   <div class="admonition mytodo">
      <p class="admonition-title">上板实验</p >
      <p>上板成功后，拍一张 FPGA 成功运行以及你的学生卡入镜头的照片，提交到实验报告中。</p>
   </div>

