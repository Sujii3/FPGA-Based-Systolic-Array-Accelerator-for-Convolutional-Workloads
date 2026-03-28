// Created by prof. Mingu Kang @VVIP Lab in UCSD ECE department
// Please do not spread this code without permission 
`timescale 1ns/1ps

module core_tb;

parameter bw = 4;
parameter psum_bw = 16;
parameter len_kij = 9;
parameter len_onij = 16; 
parameter col = 8;
parameter row = 8;
parameter len_nij = 36; 

// Weight OS

parameter len_os_nij = 8;
parameter num_ic = 8;
parameter num_oc = 8;

reg clk = 0;
reg reset = 1;

wire [37:0] inst_q;

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

// New signals for OS mode support (active during OS mode only)
reg mode_select = 0;   // 0 = Weight Stationary, 1 = Output Stationary
reg mode_select_q = 0;
reg os_drain = 0;      // Trigger OS mode drain (cascades through rows)
reg os_drain_q = 0;

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
reg [8*30:1] stringvar;
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

// Weight OS

integer activation_loading_count;
integer wfifo_wr_start;
integer wfifo_wr_end;
integer l0_wr_start;
integer l0_wr_end;
integer fifo_rd_start;
integer fifo_rd_end;
integer exec_start;
integer exec_end;
integer total_cycles;
integer sfu_delay;


assign inst_q[37] = os_drain_q;    // OS mode drain trigger
assign inst_q[36] = mode_select_q; // 0 = WS, 1 = OS
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
	.reset(reset)); 


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


//////////////////////////////////// Weight Stationary Mode Test /////////////////////////////////////


  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; reset = 1;
  #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;

  x_file = $fopen("../datafiles/activation.txt", "r");
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
     0: w_file_name = "../datafiles/weight_k1.txt";
     1: w_file_name = "../datafiles/weight_k2.txt";
     2: w_file_name = "../datafiles/weight_k3.txt";
     3: w_file_name = "../datafiles/weight_k4.txt";
     4: w_file_name = "../datafiles/weight_k5.txt";
     5: w_file_name = "../datafiles/weight_k6.txt";
     6: w_file_name = "../datafiles/weight_k7.txt";
     7: w_file_name = "../datafiles/weight_k8.txt";
     8: w_file_name = "../datafiles/weight_k9.txt";
    endcase
    

    w_file = $fopen(w_file_name, "r");
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

    for (t=0; t<col; t=t+1) begin  
      #0.5 clk = 1'b0;  w_scan_file = $fscanf(w_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1; 
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
    #0.5 clk = 1'b1; 
    /////////////////////////////////////



    /////// Kernel data writing to l0 ///////
    // starting address for weights in l0
    A_xmem = 11'b10000000000;

    for (t=0; t<col+1; t=t+1) begin
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

    for (t=0; t<col + l0_read_to_PE_load_delay; t=t+1) begin
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
  
    // COMPARED TILL HERE AND LOOKS GOOD

    ////// provide some intermission to clear up the kernel loading ///
    #0.5 clk = 1'b0;  load = 0;   l0_rd = 0;
    #0.5 clk = 1'b1;  
  

    for (i=0; i<10 ; i=i+1) begin
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


    end  // end of kij loop


  ////////// Accumulation /////////
  out_file = $fopen("../datafiles/out.txt", "r");  
  acc_file = $fopen("../datafiles/acc_scan.txt", "r");

  // Following three lines are to remove the first three comment lines of the file
  out_scan_file = $fscanf(out_file,"%s", answer); 
  out_scan_file = $fscanf(out_file,"%s", answer); 
  out_scan_file = $fscanf(out_file,"%s", answer); 

  error = 0;



  $display("############ Verification Start during accumulation #############"); 

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















/////////////////////////////////// Output Stationary Mode Test ///////////////////////////////////


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


  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; reset = 1;
  #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;
  #0.5 clk = 1'b0; #0.5 clk = 1'b1;

  x_file = $fopen("../datafiles/activation_os.txt", "r");
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
  activation_loading_count = len_kij * num_ic;
  for (t=0; t<activation_loading_count; t=t+1) begin  
    #0.5 clk = 1'b0;  x_scan_file = $fscanf(x_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1;
    #0.5 clk = 1'b1;   
  end

  #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
  #0.5 clk = 1'b1; 

  $fclose(x_file);
  ///////////////////////////////////////////////

  /// Weight data loading for all 9 kij into memory /////

    w_file = $fopen("../datafiles/weights_os.txt", "r");
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

    for (t=0; t<activation_loading_count; t=t+1) begin  
      #0.5 clk = 1'b0;  w_scan_file = $fscanf(w_file,"%32b", D_xmem); WEN_xmem = 0; CEN_xmem = 0; if (t>0) A_xmem = A_xmem + 1; 
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;  WEN_xmem = 1;  CEN_xmem = 1; A_xmem = 0;
    #0.5 clk = 1'b1; 
    /////////////////////////////////////

    #0.5 clk = 1'b0;   reset = 1;
    #0.5 clk = 1'b1; 

    for (i=0; i<10 ; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0;   reset = 0;
    #0.5 clk = 1'b1; 
    
    mode_select = 1;  // Enable OS mode
    
    fifo_rd_start = 74;  // Start reading after 36 entries in BOTH FIFOs
    
    fifo_rd_end = fifo_rd_start + activation_loading_count - 1;  // t=74 to t=145
    
    exec_start = fifo_rd_start;  // t=74

    exec_end = fifo_rd_start + activation_loading_count;  // t=74 to t=145 (72 cycles)
    
    // Total cycles: max of loading end and execution end
    total_cycles = exec_end + 1;
    if (2 * activation_loading_count > total_cycles) 
        total_cycles = 2 * activation_loading_count;
    
    for (t=0; t < total_cycles; t=t+1) begin
        #0.5
        clk = 1'b0;

        if (t < 2 * activation_loading_count) begin
            if (t[0] == 0) begin
                // Even cycle: read activation
                A_xmem = t / 2; 
                WEN_xmem = 1; CEN_xmem = 0;
            end else begin
                // Odd cycle: read weight
                A_xmem = 11'b10000000000 + (t / 2);  
                WEN_xmem = 1; CEN_xmem = 0;
            end
        end else begin
            // Done reading from XMEM
            WEN_xmem = 1; CEN_xmem = 1;
        end

        ///// L0 Write /////
        if (t >= 1 && t < 2 * activation_loading_count && t[0] == 1) begin
            l0_wr = 1;
        end else begin
            l0_wr = 0;
        end

        ///// Weight FIFO Write (reusing ififo_wr for OS mode) /////
        if (t >= 2 && t <= 2 * activation_loading_count && t[0] == 0) begin
            ififo_wr = 1;
        end else begin
            ififo_wr = 0;
        end

        ///// FIFO Read (Weight FIFO and L0) - Every cycle after pre-fill /////
        if (t >= fifo_rd_start && t <= fifo_rd_end) begin
            ififo_rd = 1;  // Reused for weight FIFO read in OS mode
            l0_rd = 1;
        end else begin
            ififo_rd = 0;
            l0_rd = 0;
        end

        ///// Execute /////
        // Execute every cycle starting 1 cycle after first FIFO read
        if (t >= exec_start && t <= exec_end) begin
            execute = 1;
        end else begin
            execute = 0;
        end
        
        #0.5
        clk = 1'b1;
    end
    
    #0.5 clk = 1'b0; execute = 0; l0_rd = 0; ififo_rd = 0; l0_wr = 0; ififo_wr = 0;
    #0.5 clk = 1'b1;
    /////////////////////////////////////

    for (i=0; i < row + col - 2; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end

    #0.5 clk = 1'b0; os_drain = 1;
    #0.5 clk = 1'b1;
    #0.5 clk = 1'b0; os_drain = 0;
    #0.5 clk = 1'b1;
    
    for (i=0; i < row+2; i=i+1) begin
      #0.5 clk = 1'b0;
      #0.5 clk = 1'b1;  
    end
    

    ////// Read from OFIFO and write to PMEM in reverse order //////
    for (i=1; i < row+1; i=i+1) begin
      #0.5 clk = 1'b0; ofifo_rd = 1; CEN_pmem = 0; WEN_pmem = 0; A_pmem = row - i;
      #0.5 clk = 1'b1;
    end
    #0.5 clk = 1'b0; ofifo_rd = 0; CEN_pmem = 1; WEN_pmem = 1;
    #0.5 clk = 1'b1;


    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;
    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;


    //// Verification of output ////
    sfu_delay = 3;
    out_file = $fopen("../datafiles/output_os.txt", "r");

    // Following four lines are to remove the first four comment lines of the file
    out_scan_file = $fscanf(out_file,"%s", captured_data);
    out_scan_file = $fscanf(out_file,"%s", captured_data);
    out_scan_file = $fscanf(out_file,"%s", captured_data);
    out_scan_file = $fscanf(out_file,"%s", captured_data);
    out_scan_file = $fscanf(out_file,"%s", captured_data);

    for (i = 0; i < row + sfu_delay; i = i + 1) begin
      #0.5 clk = 1'b0;
      // Read from PMEM for first 'row' cycles
      if (i < row) begin
        CEN_pmem = 0; WEN_pmem = 1; A_pmem = i;  // Set address i
      end else begin
        CEN_pmem = 1; WEN_pmem = 1;  // No more addresses
      end

      if (i >= sfu_delay - 2) begin
        acc = 1;
      end
      
      if (i >= sfu_delay) begin
        out_scan_file = $fscanf(out_file,"%128b", answer);
        if (core_out == answer)
          $display("%2d-th nij of all output feature maps match! :D", i-sfu_delay); 
        else begin
          $display("%2d-th nij of all output feature maps data ERROR!!", i-sfu_delay); 
          $display("core_out: %128b", core_out);
          $display("answer: %128b", answer);
          error = 1;
        end
      end

      #0.5 clk = 1'b1;
    end
  

    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;
    #0.5 clk = 1'b0;
    #0.5 clk = 1'b1;

  #10 $finish;

end

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
   sel_sram_mux_q <= sel_sram_mux;
   ififo_wr_q <= ififo_wr;
   ififo_rd_q <= ififo_rd;
   l0_rd_q    <= l0_rd;
   l0_wr_q    <= l0_wr;
   execute_q  <= execute;
   load_q     <= load;
   // New signals for OS mode
   mode_select_q <= mode_select;
   os_drain_q    <= os_drain;
end


endmodule