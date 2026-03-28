// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
`timescale 1ns/1ps

module core_tb;

reg part2;

parameter bw = 4;
parameter psum_bw = 16;
parameter len_kij = 9;
parameter len_onij = 16; // Activation is only 4x4
parameter col = 8;
parameter row = 8;
parameter len_nij = 36; // The padded activation is 6x6 so 36 len_nij to read

reg clk = 0;
reg reset = 1;

// edits
wire [33:0] inst_q; // 16 * 2 instruction size + edits

reg [1:0]  inst_w_q = 0; 
reg [bw*row-1:0] D_xmem_q = 0;
reg CEN_xmem = 1;
reg WEN_xmem = 1;
reg [10:0] A_xmem = 0;
reg CEN_xmem_q = 1;
reg WEN_xmem_q = 1;
reg [10:0] A_xmem_q = 0;
reg CEN_pmem = 1;
reg WEN_pmem = 1;
reg [10:0] A_pmem = 0;
reg CEN_pmem_q = 1;
reg WEN_pmem_q = 1;
reg [10:0] A_pmem_q = 0;
reg ofifo_rd_q = 0;
reg ififo_wr_q = 0;
reg ififo_rd_q = 0;
reg l0_rd_q = 0;
reg l0_wr_q = 0;
reg execute_q = 0; // start execute signal at top
reg load_q = 0; // start load kernel signal at top
reg acc_q = 0; // enables accumulation phase from pmem
reg acc = 0;
reg sel_sram_mux_q = 0; // select sram mux input from ofifo or sfu
reg sel_sram_mux = 0; // select sram mux input from ofifo or sfu

reg [1:0]  inst_w; 
reg [bw*row-1:0] D_xmem; // this is one word
reg [psum_bw*col-1:0] answer;


reg ofifo_rd;
reg ififo_wr;
reg ififo_rd;
reg l0_rd;
reg l0_wr;
reg execute;
reg load;
reg [8*30:1] w_file_name;
wire ofifo_valid;
wire [col*psum_bw-1:0] core_out;

integer x_file, x_scan_file ; // file_handler
integer w_file, w_scan_file ; // file_handler
integer acc_file, acc_scan_file ; // file_handler
integer out_file, out_scan_file ; // file_handler
integer captured_data; 
integer t, i, j, k, kij;
integer error;
integer l0_read_to_PE_load_delay;
integer l0_read_to_PE_exec_delay;
integer sram_wr_to_ofifo_rd_delay;

assign inst_q[33] = acc_q;
assign inst_q[32] = CEN_pmem_q;
assign inst_q[31] = WEN_pmem_q;
assign inst_q[30:20] = A_pmem_q;
assign inst_q[19]   = CEN_xmem_q;
assign inst_q[18]   = WEN_xmem_q;
assign inst_q[17:7] = A_xmem_q;
assign inst_q[6]   = ofifo_rd_q;
assign inst_q[5]   = ififo_wr_q;
assign inst_q[4]   = ififo_rd_q;
assign inst_q[3]   = l0_rd_q;
assign inst_q[2]   = l0_wr_q;
assign inst_q[1]   = execute_q; 
assign inst_q[0]   = load_q; 


core  #(.bw(bw), .col(col), .row(row)) core_instance (
	.clk(clk), 
	.inst(inst_q),
	.ofifo_valid(ofifo_valid),
  .D_xmem(D_xmem_q), 
  .sfu_out(core_out), 
	.reset(reset),
  .part2(part2)
  ); 


initial begin 

  inst_w   = 0; 
  D_xmem   = 0;
  CEN_xmem = 1;
  WEN_xmem = 1;
  A_xmem   = 0;
  ofifo_rd = 0;
  ififo_wr = 0;
  ififo_rd = 0;
  l0_rd    = 0;
  l0_wr    = 0;
  execute  = 0;
  load     = 0;

  $dumpfile("core_tb.vcd");
  $dumpvars(0,core_tb);

  // start of 8x8 tb
  part2 = 0;
  x_file = $fopen("../datafiles/part1_files/activation.txt", "r");
  // Following three lines are to remove the first three comment lines of the file
  x_scan_file = $fscanf(x_file,"%s", captured_data);
  x_scan_file = $fscanf(x_file,"%s", captured_data);
  x_scan_file = $fscanf(x_file,"%s", captured_data);

  //////// Reset /////////
  #0.5 clk = 1'b0;   reset = 1;
  #0.5 clk = 1'b1; 

  for (i=0; i<10 ; i=i+1) begin
    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;   reset = 0;
  #0.5 clk = 1'b1; 

  #0.5 clk = 1'b0;   
  #0.5 clk = 1'b1;   
  /////////////////////////

  /////// Activation data writing to memory ///////
  for (t=0; t<len_nij; t=t+1) begin  
    #0.5 clk = 1'b0;  x_scan_file = $fscanf(x_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1;
    #0.5 clk = 1'b1;   
  end

  #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1; 

  $fclose(x_file);
  /////////////////////////////////////////////////

  for (kij=0; kij<9; kij=kij+1) begin  // kij loop
    case(kij)
      0: w_file = $fopen("../datafiles/part1_files/weight_k1.txt", "r");
      1: w_file = $fopen("../datafiles/part1_files/weight_k2.txt", "r");
      2: w_file = $fopen("../datafiles/part1_files/weight_k3.txt", "r");
      3: w_file = $fopen("../datafiles/part1_files/weight_k4.txt", "r");
      4: w_file = $fopen("../datafiles/part1_files/weight_k5.txt", "r");
      5: w_file = $fopen("../datafiles/part1_files/weight_k6.txt", "r");
      6: w_file = $fopen("../datafiles/part1_files/weight_k7.txt", "r");
      7: w_file = $fopen("../datafiles/part1_files/weight_k8.txt", "r");
      8: w_file = $fopen("../datafiles/part1_files/weight_k9.txt", "r");
    endcase
    // Following three lines are to remove the first three comment lines of the file
    w_scan_file = $fscanf(w_file,"%s", captured_data);
    w_scan_file = $fscanf(w_file,"%s", captured_data);
    w_scan_file = $fscanf(w_file,"%s", captured_data);

    #0.5 clk = 1'b0;   reset = 1;
    #0.5 clk = 1'b1; 

    for (i=0; i<10 ; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;   reset = 0;
    #0.5 clk = 1'b1; 

    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   


    /////// Kernel data writing to memory ///////
    A_xmem = 11'b10000000000;
    for (t=0; t < col; t=t+1) begin  
      #0.5 clk = 1'b0;  w_scan_file = $fscanf(w_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1; 
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
    #0.5 clk = 1'b1; 
    /////////////////////////////////////

    
    /////// Kernel data writing to l0 ///////
    // starting address for weights in l0
    A_xmem = 11'b10000000000;

    for (t=0; t < col + 1; t=t+1) begin
        #0.5
        clk = 1'b0;

        // for every cycle but LAST one
        if (t != col) begin 
            if (t>0) A_xmem = A_xmem + 1; // increment A_xmem if its not first cycle
            WEN_xmem = 1; CEN_xmem = 0; // write out from L0 kernel weight at A_xmem
        end else begin
            WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0; // disable xmem, and set address to 0
        end

        // for every cycle but FIRST one
        if (t != 0) begin
            l0_wr = 1; // write a full row into l0
        end
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0; l0_wr = 0; // turn off l0 writing
    #0.5 clk = 1'b1; 

    /////////////////////////////////////

    /////// Kernel loading to PEs ///////

    // (core) l0_rd_q -> (ififo) rd_en +1
    // (ififo) rd_en -> (fifo_depth64) data out +0
    // (ififo) out / (core) l0_to_array -> (mac_tile) in_w +0
    // (mac_tile) in_w -> data stored +1

    // (core) load_q -> (mac_array) inst_w + 0
    // (mac_array) inst_w -> (mac_row) inst_w + 1
    // (mac_row) inst_w -> (mac_tile) inst_w + 0
    // (mac_tile) inst_w -> data stored +1

    // 2 - 2 = 0
    l0_read_to_PE_load_delay = 0;

    for (t=0; t < col + l0_read_to_PE_load_delay; t=t+1) begin
        #0.5
        clk = 1'b0;

        if (t < col) begin
            // read from l0 for first col cycles
            l0_rd = 1'b1;
        end else begin
            l0_rd = 1'b0;
        end

        if (t >= l0_read_to_PE_load_delay) begin
            load = 1'b1;
        end
        
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0;  load = 0;  l0_rd = 0; // turn off l0 writing
    #0.5 clk = 1'b1; 
    /////////////////////////////////////


    ////// provide some intermission to clear up the kernel loading ///
    #0.5 clk = 1'b0;  load = 0;   l0_rd = 0;
    #0.5 clk = 1'b1;  
  

    for (i=0; i<20 ; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end
    /////////////////////////////////////



    /////// Activation data writing to L0 ///////
    A_xmem = 0;

    for (t=0; t<len_nij + 1; t=t+1) begin  
        #0.5 clk = 1'b0;

        // for every cycle but LAST one
        if (t != len_nij) begin 
            if (t>0) A_xmem = A_xmem + 1; // increment A_xmem if its not first cycle
            WEN_xmem = 1; CEN_xmem = 0; // write out from xmem at A_xmem
        end else begin
            WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0; // disable xmem, and set address to 0
        end

        // for every cycle but FIRST one
        if (t != 0) begin
            l0_wr = 1; // write a full row into l0
        end

        #0.5 clk = 1'b1;   
    end

    #0.5 clk = 1'b0; l0_wr = 0; // turn off l0 writing
    #0.5 clk = 1'b1; 
    /////////////////////////////////////



    /////// Execution ///////
    l0_read_to_PE_exec_delay = 1;

    for (t=0; t<len_nij + l0_read_to_PE_exec_delay; t=t+1) begin
        #0.5
        clk = 1'b0;

        if (t < len_nij) begin
            // read from l0 for first col cycles
            l0_rd = 1'b1;
        end else begin
            l0_rd = 1'b0;
        end

        if (t >= l0_read_to_PE_exec_delay) begin
            execute = 1'b1;
        end
        
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0;  execute = 0;  l0_rd = 0; // turn off l0 reading
    #0.5 clk = 1'b1; 
    /////////////////////////////////////



    //////// OFIFO READ ////////
    // Ideally, OFIFO should be read while execution, but we have enough ofifo
    // depth so we can fetch out after execution.
    sram_wr_to_ofifo_rd_delay = 1;
    A_pmem = kij * len_nij;

    for (t=0; t<len_nij + sram_wr_to_ofifo_rd_delay; t=t+1) begin 
        #0.5
        clk = 1'b0;

        if (t < len_nij) begin
            // read from ofifo
            WEN_pmem = 1'b0;
            CEN_pmem = 1'b0;
            if (t != 0) begin A_pmem = A_pmem+1; end
        end else begin
            WEN_pmem = 1'b1;
            CEN_pmem = 1'b1;
        end

        if (t >= sram_wr_to_ofifo_rd_delay) begin
            ofifo_rd = 1'b1;
        end
        
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0; WEN_pmem = 1'b1; CEN_pmem = 1'b1; A_pmem = 0; ofifo_rd = 1'b0; // turn off sram write
    #0.5 clk = 1'b1; 
    /////////////////////////////////////

    $fclose(w_file);
    end  // end of kij loop


  ////////// Accumulation /////////
  out_file = $fopen("../datafiles/part1_files/out.txt", "r");  
  acc_file = $fopen("../datafiles/acc_scan.txt", "r");
  
  // Following three lines are to remove the first three comment lines of the file
  out_scan_file = $fscanf(out_file,"%s", answer); 
  out_scan_file = $fscanf(out_file,"%s", answer); 
  out_scan_file = $fscanf(out_file,"%s", answer); 

  error = 0;

  $display("############ Verification Start during accumulation of Part1 #############"); 

  for (i=0; i<len_onij+1; i=i+1) begin 

    #0.5 clk = 1'b0; 
    #0.5 clk = 1'b1; 

    if (i>0) begin
     out_scan_file = $fscanf(out_file,"%128b", answer); // reading from out file to answer
       if (core_out == answer)
         $display("%2d-th output featuremap Data matched! :D", i); 
       else begin
         $display("%2d-th output featuremap Data ERROR!!", i); 
         $display("core_out: %128b", core_out);
         $display("answer: %128b", answer);
         error = 1;
       end
    end
   
 
    #0.5 clk = 1'b0; reset = 1;
    #0.5 clk = 1'b1;  
    #0.5 clk = 1'b0; reset = 0; 
    #0.5 clk = 1'b1;  

    for (j=0; j<len_kij+1; j=j+1) begin 

      #0.5 clk = 1'b0;   
        if (j<len_kij) begin CEN_pmem = 0; WEN_pmem = 1; acc_scan_file = $fscanf(acc_file,"%11b", A_pmem); end
                       else  begin CEN_pmem = 1; WEN_pmem = 1; end

        if (j>0)  acc = 1;  
      #0.5 clk = 1'b1;   
    end

    #0.5 clk = 1'b0; acc = 0;
    #0.5 clk = 1'b1; 
  end


  if (error == 0) begin
  	$display("############ No error detected ##############"); 
  	$display("########### Project Completed !! ############"); 

  end

  $fclose(out_file);
  $fclose(acc_file);
  //////////////////////////////////

  for (t=0; t<10; t=t+1) begin  
    #0.5 clk = 1'b0;  
    #0.5 clk = 1'b1;  
  end

  // finish of 8x8

  // start of 16x8
  part2 = 1;
  x_file = $fopen("../datafiles/part2_files/activation.txt", "r");
  // Following three lines are to remove the first three comment lines of the file
  x_scan_file = $fscanf(x_file,"%s", captured_data);
  x_scan_file = $fscanf(x_file,"%s", captured_data);
  x_scan_file = $fscanf(x_file,"%s", captured_data);

  //////// Reset /////////
  #0.5 clk = 1'b0;   reset = 1;
  #0.5 clk = 1'b1; 

  for (i=0; i<10 ; i=i+1) begin
    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;  
  end

  #0.5 clk = 1'b0;   reset = 0;
  #0.5 clk = 1'b1; 

  #0.5 clk = 1'b0;   
  #0.5 clk = 1'b1;   
  /////////////////////////

  /////// Activation data writing to memory ///////
  for (t=0; t<len_nij; t=t+1) begin  
    #0.5 clk = 1'b0;  x_scan_file = $fscanf(x_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1;
    #0.5 clk = 1'b1;   
  end

  #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1; 

  $fclose(x_file);
  /////////////////////////////////////////////////

  for (kij=0; kij<9; kij=kij+1) begin  // kij loop
    case(kij)
      0: w_file = $fopen("../datafiles/part2_files/weight_k1.txt", "r");
      1: w_file = $fopen("../datafiles/part2_files/weight_k2.txt", "r");
      2: w_file = $fopen("../datafiles/part2_files/weight_k3.txt", "r");
      3: w_file = $fopen("../datafiles/part2_files/weight_k4.txt", "r");
      4: w_file = $fopen("../datafiles/part2_files/weight_k5.txt", "r");
      5: w_file = $fopen("../datafiles/part2_files/weight_k6.txt", "r");
      6: w_file = $fopen("../datafiles/part2_files/weight_k7.txt", "r");
      7: w_file = $fopen("../datafiles/part2_files/weight_k8.txt", "r");
      8: w_file = $fopen("../datafiles/part2_files/weight_k9.txt", "r");
    endcase
    // Following three lines are to remove the first three comment lines of the file
    w_scan_file = $fscanf(w_file,"%s", captured_data);
    w_scan_file = $fscanf(w_file,"%s", captured_data);
    w_scan_file = $fscanf(w_file,"%s", captured_data);

    #0.5 clk = 1'b0;   reset = 1;
    #0.5 clk = 1'b1; 

    for (i=0; i<10 ; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;   reset = 0;
    #0.5 clk = 1'b1; 

    #0.5 clk = 1'b0;   
    #0.5 clk = 1'b1;   


    /////// Kernel data writing to memory ///////
    A_xmem = 11'b10000000000;
    for (t=0; t < 2*col; t=t+1) begin  
      #0.5 clk = 1'b0;  w_scan_file = $fscanf(w_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1; 
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
    #0.5 clk = 1'b1; 
    /////////////////////////////////////

    
    /////// Kernel data writing to l0 ///////
    // starting address for weights in l0
    A_xmem = 11'b10000000000;

    for (t=0; t < 2*col + 1; t=t+1) begin
        #0.5
        clk = 1'b0;

        // for every cycle but LAST one
        if (t != 2*col) begin 
            if (t>0) A_xmem = A_xmem + 1; // increment A_xmem if its not first cycle
            WEN_xmem = 1; CEN_xmem = 0; // write out from L0 kernel weight at A_xmem
        end else begin
            WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0; // disable xmem, and set address to 0
        end

        // for every cycle but FIRST one
        if (t != 0) begin
            l0_wr = 1; // write a full row into l0
        end
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0; l0_wr = 0; // turn off l0 writing
    #0.5 clk = 1'b1; 

    /////////////////////////////////////

    /////// Kernel loading to PEs ///////

    // (core) l0_rd_q -> (ififo) rd_en +1
    // (ififo) rd_en -> (fifo_depth64) data out +0
    // (ififo) out / (core) l0_to_array -> (mac_tile) in_w +0
    // (mac_tile) in_w -> data stored +1

    // (core) load_q -> (mac_array) inst_w + 0
    // (mac_array) inst_w -> (mac_row) inst_w + 1
    // (mac_row) inst_w -> (mac_tile) inst_w + 0
    // (mac_tile) inst_w -> data stored +1

    // 2 - 2 = 0
    l0_read_to_PE_load_delay = 0;

    for (t=0; t < 2*col + l0_read_to_PE_load_delay; t=t+1) begin
        #0.5
        clk = 1'b0;

        if (t < 2*col) begin
            // read from l0 for first col cycles
            l0_rd = 1'b1;
        end else begin
            l0_rd = 1'b0;
        end

        if (t >= l0_read_to_PE_load_delay) begin
            load = 1'b1;
        end
        
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0;  load = 0;  l0_rd = 0; // turn off l0 writing
    #0.5 clk = 1'b1; 
    /////////////////////////////////////


    ////// provide some intermission to clear up the kernel loading ///
    #0.5 clk = 1'b0;  load = 0;   l0_rd = 0;
    #0.5 clk = 1'b1;  
  

    for (i=0; i<20 ; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end
    /////////////////////////////////////



    /////// Activation data writing to L0 ///////
    A_xmem = 0;

    for (t=0; t<len_nij + 1; t=t+1) begin  
        #0.5 clk = 1'b0;

        // for every cycle but LAST one
        if (t != len_nij) begin 
            if (t>0) A_xmem = A_xmem + 1; // increment A_xmem if its not first cycle
            WEN_xmem = 1; CEN_xmem = 0; // write out from xmem at A_xmem
        end else begin
            WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0; // disable xmem, and set address to 0
        end

        // for every cycle but FIRST one
        if (t != 0) begin
            l0_wr = 1; // write a full row into l0
        end

        #0.5 clk = 1'b1;   
    end

    #0.5 clk = 1'b0; l0_wr = 0; // turn off l0 writing
    #0.5 clk = 1'b1; 
    /////////////////////////////////////



    /////// Execution ///////
    l0_read_to_PE_exec_delay = 1;

    for (t=0; t<len_nij + l0_read_to_PE_exec_delay; t=t+1) begin
        #0.5
        clk = 1'b0;

        if (t < len_nij) begin
            // read from l0 for first col cycles
            l0_rd = 1'b1;
        end else begin
            l0_rd = 1'b0;
        end

        if (t >= l0_read_to_PE_exec_delay) begin
            execute = 1'b1;
        end
        
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0;  execute = 0;  l0_rd = 0; // turn off l0 reading
    #0.5 clk = 1'b1; 
    /////////////////////////////////////



    //////// OFIFO READ ////////
    // Ideally, OFIFO should be read while execution, but we have enough ofifo
    // depth so we can fetch out after execution.
    sram_wr_to_ofifo_rd_delay = 1;
    A_pmem = kij * len_nij;

    for (t=0; t<len_nij + sram_wr_to_ofifo_rd_delay; t=t+1) begin 
        #0.5
        clk = 1'b0;

        if (t < len_nij) begin
            // read from ofifo
            WEN_pmem = 1'b0;
            CEN_pmem = 1'b0;
            if (t != 0) begin A_pmem = A_pmem+1; end
        end else begin
            WEN_pmem = 1'b1;
            CEN_pmem = 1'b1;
        end

        if (t >= sram_wr_to_ofifo_rd_delay) begin
            ofifo_rd = 1'b1;
        end
        
        #0.5
        clk = 1'b1;
    end
    #0.5 clk = 1'b0; WEN_pmem = 1'b1; CEN_pmem = 1'b1; A_pmem = 0; ofifo_rd = 1'b0; // turn off sram write
    #0.5 clk = 1'b1; 
    /////////////////////////////////////

    $fclose(w_file);
    end  // end of kij loop


  ////////// Accumulation /////////
  out_file = $fopen("../datafiles/part2_files/out.txt", "r");  
  acc_file = $fopen("../datafiles/acc_scan.txt", "r");
  
  // Following three lines are to remove the first three comment lines of the file
  out_scan_file = $fscanf(out_file,"%s", answer); 
  out_scan_file = $fscanf(out_file,"%s", answer); 
  out_scan_file = $fscanf(out_file,"%s", answer); 

  error = 0;

  $display("############ Verification Start during accumulation of Part2 #############"); 

  for (i=0; i<len_onij+1; i=i+1) begin 

    #0.5 clk = 1'b0; 
    #0.5 clk = 1'b1; 

    if (i>0) begin
     out_scan_file = $fscanf(out_file,"%128b", answer); // reading from out file to answer
       if (core_out == answer)
         $display("%2d-th output featuremap Data matched! :D", i); 
       else begin
         $display("%2d-th output featuremap Data ERROR!!", i); 
         $display("core_out: %128b", core_out);
         $display("answer: %128b", answer);
         error = 1;
       end
    end
   
 
    #0.5 clk = 1'b0; reset = 1;
    #0.5 clk = 1'b1;  
    #0.5 clk = 1'b0; reset = 0; 
    #0.5 clk = 1'b1;  

    for (j=0; j<len_kij+1; j=j+1) begin 

      #0.5 clk = 1'b0;   
        if (j<len_kij) begin CEN_pmem = 0; WEN_pmem = 1; acc_scan_file = $fscanf(acc_file,"%11b", A_pmem); end
                       else  begin CEN_pmem = 1; WEN_pmem = 1; end

        if (j>0)  acc = 1;  
      #0.5 clk = 1'b1;   
    end

    #0.5 clk = 1'b0; acc = 0;
    #0.5 clk = 1'b1; 
  end


  if (error == 0) begin
  	$display("############ No error detected ##############"); 
  	$display("########### Project Completed !! ############"); 

  end

  $fclose(acc_file);
  //////////////////////////////////

  for (t=0; t<10; t=t+1) begin  
    #0.5 clk = 1'b0;  
    #0.5 clk = 1'b1;  
  end

  // finish of 16x8

  #10 $finish;

end

// TODO: Should this really be posedge clk?
// If so maybe change SFU and wait for next clk posedge
always @ (posedge clk) begin
   inst_w_q   <= inst_w; 
   D_xmem_q   <= D_xmem;
   CEN_xmem_q <= CEN_xmem;
   WEN_xmem_q <= WEN_xmem;
   A_pmem_q   <= A_pmem;
   CEN_pmem_q <= CEN_pmem;
   WEN_pmem_q <= WEN_pmem;
   A_xmem_q   <= A_xmem;
   ofifo_rd_q <= ofifo_rd;
   acc_q      <= acc;
   sel_sram_mux_q <= sel_sram_mux; // edit
   ififo_wr_q <= ififo_wr;
   ififo_rd_q <= ififo_rd;
   l0_rd_q    <= l0_rd;
   l0_wr_q    <= l0_wr ;
   execute_q  <= execute;
   load_q     <= load;
end


endmodule