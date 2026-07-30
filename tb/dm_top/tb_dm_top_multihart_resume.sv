// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
//
// Checks multi-hart resume requests through the complete debug-module path
// The default test uses three harts with a non-trivial selectable-hart mask
// All variants drive both DMI DMControl and debug-memory Resuming writes

module tb_dm_top_multihart_resume #(
  parameter int unsigned NrHarts = 3,
  parameter logic [NrHarts-1:0] SelectableHarts =
      (NrHarts == 3) ? 3'b101 : {NrHarts{1'b1}}
);

  localparam logic [11:0] HaltedAddr   = 12'h100;
  localparam logic [11:0] ResumingAddr = 12'h110;
  localparam int unsigned HartOne = (NrHarts > 1) ? 1 : 0;
  localparam int unsigned HartTwo = (NrHarts > 2) ? 2 : 0;
  localparam int unsigned LastHart = NrHarts - 1;

  logic clk, rst_n;

  logic ndmreset, dmactive;

  logic        slave_req, slave_we;
  logic [31:0] slave_addr, slave_wdata;

  logic dmi_req_valid, dmi_req_ready;
  dm::dmi_req_t dmi_req;
  logic dmi_resp_valid;
  dm::dmi_resp_t dmi_resp;

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  dm_top #(
    .NrHarts       ( NrHarts       ),
    .BusWidth      ( 32            ),
    .SelectableHarts ( SelectableHarts )
  ) dut (
    .clk_i                  ( clk             ),
    .rst_ni                 ( rst_n           ),
    .next_dm_addr_i         ( '0              ),
    .testmode_i             ( 1'b0            ),
    .ndmreset_o             ( ndmreset        ),
    .ndmreset_ack_i         ( 1'b0            ),
    .dmactive_o             ( dmactive        ),
    .debug_req_o            (                 ),
    .unavailable_i          ( '0              ),
    .hartinfo_i             ( '0              ),
    .slave_req_i            ( slave_req       ),
    .slave_we_i             ( slave_we        ),
    .slave_addr_i           ( slave_addr      ),
    .slave_be_i             ( '1              ),
    .slave_wdata_i          ( slave_wdata     ),
    .slave_rdata_o          (                 ),
    .master_req_o           (                 ),
    .master_add_o           (                 ),
    .master_we_o            (                 ),
    .master_wdata_o         (                 ),
    .master_be_o            (                 ),
    .master_gnt_i           ( 1'b0            ),
    .master_r_valid_i       ( 1'b0            ),
    .master_r_err_i         ( 1'b0            ),
    .master_r_other_err_i   ( 1'b0            ),
    .master_r_rdata_i       ( '0              ),
    .dmi_rst_ni             ( rst_n           ),
    .dmi_req_valid_i        ( dmi_req_valid   ),
    .dmi_req_ready_o        ( dmi_req_ready   ),
    .dmi_req_i              ( dmi_req         ),
    .dmi_resp_valid_o       ( dmi_resp_valid  ),
    .dmi_resp_ready_i       ( 1'b1            ),
    .dmi_resp_o             ( dmi_resp        )
  );

  task automatic write_dmcontrol(
    input logic [19:0] hartsel,
    input logic        request_resume,
    input logic        request_ndmreset,
    input logic        request_haltreq = 1'b0,
    input logic        request_dmactive = 1'b1
  );
    dm::dmcontrol_t dmcontrol;

    if (clk !== 1'b0) begin
      @(negedge clk);
    end
    dmcontrol            = '0;
    dmcontrol.hartsello  = hartsel[9:0];
    dmcontrol.hartselhi  = hartsel[19:10];
    dmcontrol.haltreq    = request_haltreq;
    dmcontrol.resumereq  = request_resume;
    dmcontrol.ndmreset   = request_ndmreset;
    dmcontrol.dmactive   = request_dmactive;

    while (!dmi_req_ready) begin
      @(negedge clk);
    end
    dmi_req.data  = dmcontrol;
    dmi_req_valid = 1'b1;
    @(posedge clk);
    if (!dmi_req_ready) begin
      $fatal(1, "DMI request was not accepted");
    end

    @(negedge clk);
    dmi_req_valid = 1'b0;
    #1ns;
    if (!dmi_resp_valid || dmi_resp.resp != dm::DTM_SUCCESS || dmi_resp.data != '0) begin
      $fatal(1, "DMControl write for hartsel %0d failed (resp=%0d data=%08x)",
             hartsel, dmi_resp.resp, dmi_resp.data);
    end
    // Let the response FIFO pop before issuing the next request
    @(posedge clk);
  endtask

  task automatic expect_dmcontrol_resumereq_zero;
    if (clk !== 1'b0) begin
      @(negedge clk);
    end
    dmi_req.op    = dm::DTM_READ;
    dmi_req_valid = 1'b1;
    @(posedge clk);
    if (!dmi_req_ready) begin
      $fatal(1, "DMControl read was not accepted");
    end
    @(negedge clk);
    dmi_req_valid = 1'b0;
    #1ns;
    if (!dmi_resp_valid || dmi_resp.resp != dm::DTM_SUCCESS ||
        dmi_resp.data[30] !== 1'b0) begin
      $fatal(1, "DMControl resumereq is not read-zero (data=%08x)", dmi_resp.data);
    end
    dmi_req.op = dm::DTM_WRITE;
    @(posedge clk);
  endtask

  // Exercise memory-write-over-clear and ndmreset-over-clear/ack precedence
  // by accepting the DMI write and ResumingAddr write on the same clock edge
  task automatic write_dmcontrol_and_resuming(
    input logic [19:0] hartsel,
    input logic        request_resume,
    input logic        request_ndmreset,
    input int unsigned resuming_hart
  );
    dm::dmcontrol_t dmcontrol;

    dmcontrol            = '0;
    dmcontrol.hartsello  = hartsel[9:0];
    dmcontrol.hartselhi  = hartsel[19:10];
    dmcontrol.resumereq  = request_resume;
    dmcontrol.ndmreset   = request_ndmreset;
    dmcontrol.dmactive   = 1'b1;

    @(negedge clk);
    while (!dmi_req_ready) begin
      @(negedge clk);
    end
    dmi_req.data  = dmcontrol;
    dmi_req_valid = 1'b1;
    slave_we      = 1'b1;
    slave_req     = 1'b1;
    slave_addr    = 32'(ResumingAddr);
    slave_wdata   = 32'(resuming_hart);
    @(posedge clk);
    @(negedge clk);
    dmi_req_valid = 1'b0;
    slave_req     = 1'b0;
    #1ns;
    if (!dmi_resp_valid || dmi_resp.resp != dm::DTM_SUCCESS || dmi_resp.data != '0) begin
      $fatal(1, "combined DMControl/ResumingAddr write failed");
    end
    @(posedge clk);
  endtask

  task automatic write_debug_memory(input logic [11:0] address, input int unsigned hart);
    @(negedge clk);
    slave_we    = 1'b1;
    slave_req   = 1'b1;
    slave_addr  = 32'(address);
    slave_wdata = 32'(hart);
    @(posedge clk);
    @(negedge clk);
    slave_req   = 1'b0;
  endtask

  task automatic read_debug_memory(input logic [11:0] address, output logic [31:0] data);
    @(negedge clk);
    slave_we    = 1'b0;
    slave_req   = 1'b1;
    slave_addr  = 32'(address);
    slave_wdata = '0;
    @(posedge clk);
    #1ns;
    data        = dut.slave_rdata_o;
    @(negedge clk);
    slave_req   = 1'b0;
    slave_we    = 1'b1;
  endtask

  task automatic expect_resume_request(input int unsigned hart, input logic expected);
    #1ns;
    if (dut.resumereq[hart] !== expected) begin
      $fatal(1, "resumereq[%0d]=%0b, expected %0b", hart, dut.resumereq[hart], expected);
    end
  endtask

  task automatic expect_resume_ack(input int unsigned hart, input logic expected);
    #1ns;
    if (dut.resumeack[hart] !== expected) begin
      $fatal(1, "resumeack[%0d]=%0b, expected %0b", hart, dut.resumeack[hart], expected);
    end
  endtask

  task automatic expect_halted(input int unsigned hart, input logic expected);
    #1ns;
    if (dut.halted[hart] !== expected) begin
      $fatal(1, "halted[%0d]=%0b, expected %0b", hart, dut.halted[hart], expected);
    end
  endtask

  task automatic expect_resume_ack_vector(input logic [NrHarts-1:0] expected);
    #1ns;
    if (dut.resumeack !== expected) begin
      $fatal(1, "resumeack=%b, expected %b", dut.resumeack, expected);
    end
  endtask

  task automatic expect_resume_flag(input int unsigned hart, input logic expected);
    logic [31:0] data;

    read_debug_memory(12'(12'h400 + hart), data);
    if (data[(hart & 3) * 8 + 1] !== expected) begin
      $fatal(1, "resume flag[%0d]=%0b, expected %0b (data=%08x)",
             hart, data[(hart & 3) * 8 + 1], expected, data);
    end
  endtask

  task automatic expect_halted_vector(input logic [NrHarts-1:0] expected);
    #1ns;
    if (dut.halted !== expected) begin
      $fatal(1, "halted=%b, expected %b", dut.halted, expected);
    end
  endtask

  initial begin
    logic [NrHarts-1:0] resumeack_before_invalid;
    logic [NrHarts-1:0] expected_resumeack_before_ndmreset;

    rst_n       = 1'b0;
    slave_req   = 1'b0;
    slave_we    = 1'b1;
    slave_addr  = '0;
    slave_wdata = '0;
    dmi_req_valid = 1'b0;
    dmi_req       = '0;
    dmi_req.addr  = 7'(dm::DMControl);
    dmi_req.op    = dm::DTM_WRITE;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1ns;

    // Activate the DM
    write_dmcontrol(0, 1'b0, 1'b0);
    if (!dmactive) begin
      $fatal(1, "debug module did not become active");
    end

    if (NrHarts == 3) begin
      // Harts 0 and 2 are selectable; hart 1 is intentionally masked out to
      // exercise the non-trivial SelectableHarts parameter
      // Leave hart 2's acknowledgement stale, then request hart 0
      write_debug_memory(HaltedAddr, HartTwo);
      write_debug_memory(ResumingAddr, HartTwo);
      expect_resume_ack(HartTwo, 1'b1);
      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(ResumingAddr, 0);
      expect_resume_ack(0, 1'b1);
      write_debug_memory(HaltedAddr, 0);
      write_dmcontrol(0, 1'b1, 1'b0, 1'b1);
      expect_resume_request(0, 1'b0);
      expect_resume_ack(0, 1'b1);
      write_dmcontrol(0, 1'b1, 1'b0);
      expect_resume_request(0, 1'b1);
      expect_resume_ack(HartTwo, 1'b1);

      // Accept a second request without retiring the first one
      write_debug_memory(HaltedAddr, HartTwo);
      write_dmcontrol(20'(HartTwo), 1'b1, 1'b0);
      expect_resume_request(HartTwo, 1'b1);
      expect_resume_request(0, 1'b1);
      expect_resume_ack(HartTwo, 1'b0);
      // A non-requesting write changes hartsel but cannot cancel either action
      write_dmcontrol(20'(HartTwo), 1'b0, 1'b0);
      expect_dmcontrol_resumereq_zero();
      expect_resume_flag(0, 1'b1);
      expect_resume_flag(HartTwo, 1'b1);

      // Acknowledge the two harts independently
      write_debug_memory(ResumingAddr, HartTwo);
      expect_resume_ack(HartTwo, 1'b1);
      @(posedge clk);
      expect_resume_request(HartTwo, 1'b0);
      expect_resume_request(0, 1'b1);
      expect_resume_flag(0, 1'b1);
      write_debug_memory(ResumingAddr, 0);
      @(posedge clk);
      expect_resume_request(0, 1'b0);
      expect_resume_request(HartTwo, 1'b0);

      // A stale acknowledgement is cleared for the effective target
      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(ResumingAddr, 0);
      expect_resume_ack(0, 1'b1);
      write_debug_memory(HaltedAddr, 0);
      write_dmcontrol(20'd0, 1'b1, 1'b0);
      expect_resume_request(0, 1'b1);
      expect_resume_ack(0, 1'b0);

      // A memory acknowledgement on the same edge as a new request's clear
      // must win over the clear, leaving resumeack set for completion
      write_dmcontrol_and_resuming(20'd0, 1'b1, 1'b0, 0);
      expect_resume_ack(0, 1'b1);
      expect_resume_request(0, 1'b0);

      // Raw hartsel=4 is WARL-masked to hart 0 for NrHarts=3.  A stale
      // acknowledgement must be cleared for the effective target, and the
      // resulting request must remain outstanding until a fresh acknowledgement
      write_debug_memory(HaltedAddr, 0);
      write_dmcontrol(20'd4, 1'b1, 1'b0);
      expect_resume_request(0, 1'b1);
      expect_resume_ack(0, 1'b0);
      write_debug_memory(ResumingAddr, 0);
      @(posedge clk);
      expect_resume_request(0, 1'b0);

      // Raw hartsel=3 is effective-invalid for NrHarts=3.  It must neither
      // clear an acknowledgement nor create a request for any valid hart
      expect_resume_ack(HartTwo, 1'b1);
      resumeack_before_invalid = dut.resumeack;
      write_dmcontrol(20'd3, 1'b1, 1'b0);
      if (dut.resumeack !== resumeack_before_invalid || dut.resumereq !== '0) begin
        $fatal(1, "invalid hartsel changed per-hart resume state");
      end
      // Recover from the invalid selection with a valid, non-requesting write
      write_dmcontrol(0, 1'b0, 1'b0);
      if (dut.resumereq !== '0 || dut.resumeack !== resumeack_before_invalid) begin
        $fatal(1, "invalid hartsel recovery changed resume state");
      end

      // Hart 1 is masked out, so its request and acknowledgement are ignored
      write_debug_memory(HaltedAddr, HartOne);
      write_dmcontrol(20'(HartOne), 1'b1, 1'b0);
      expect_resume_request(HartOne, 1'b0);
      expect_resume_ack(0, 1'b1);
      write_debug_memory(ResumingAddr, HartOne);
      expect_resume_ack(HartOne, 1'b0);
      expect_resume_ack(0, 1'b1);

      // Deactivating the debug module clears all pending actions
      write_debug_memory(HaltedAddr, HartTwo);
      write_dmcontrol(20'(HartTwo), 1'b1, 1'b0);
      expect_resume_request(HartTwo, 1'b1);
      write_dmcontrol(20'(HartTwo), 1'b0, 1'b0, 1'b0, 1'b0);
      if (dmactive || dut.resumereq !== '0) begin
        $fatal(1, "DM deactivation retained resume state");
      end
      write_dmcontrol(0, 1'b0, 1'b0);
      if (!dmactive) begin
        $fatal(1, "debug module did not reactivate");
      end

      // Keep a request outstanding across ndmreset.  dm_mem clears its halted,
      // resuming, and FSM state, while dm_csrs retains the pending action
      write_debug_memory(HaltedAddr, HartTwo);
      write_dmcontrol(20'(HartTwo), 1'b1, 1'b0);
      expect_resume_request(HartTwo, 1'b1);
      write_dmcontrol(20'(HartTwo), 1'b1, 1'b1);
      @(posedge clk);
      #1ns;
      if (!ndmreset) begin
        $fatal(1, "ndmreset did not assert");
      end
      expect_halted(HartTwo, 1'b0);
      expect_resume_ack(HartTwo, 1'b0);
      expect_resume_request(HartTwo, 1'b1);

      // Deassert ndmreset, re-establish halted state, and complete the retained
      // request. The concurrent ResumingAddr write is suppressed by ndmreset
      write_dmcontrol_and_resuming(20'(HartTwo), 1'b1, 1'b0, HartTwo);
      if (ndmreset) begin
        $fatal(1, "ndmreset did not deassert");
      end
      expect_resume_ack(HartTwo, 1'b0);
      write_debug_memory(HaltedAddr, HartTwo);
      expect_halted(HartTwo, 1'b1);
      write_debug_memory(ResumingAddr, HartTwo);
      expect_resume_ack(HartTwo, 1'b1);
      @(posedge clk);
      expect_resume_request(HartTwo, 1'b0);
    end else if (NrHarts == 1) begin
      // The singleton case still exercises stale-ack clearing and normal
      // request completion before checking the full-vector reset behavior
      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(ResumingAddr, 0);
      expect_resume_ack(0, 1'b1);
      write_debug_memory(HaltedAddr, 0);
      write_dmcontrol(0, 1'b1, 1'b0);
      expect_resume_ack(0, 1'b0);
      expect_resume_request(0, 1'b1);
      write_debug_memory(ResumingAddr, 0);
      expect_resume_ack(0, 1'b1);
      @(posedge clk);
      expect_resume_request(0, 1'b0);

      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(ResumingAddr, 0);
      write_debug_memory(HaltedAddr, 0);
      expect_halted_vector('1);
      expect_resume_ack_vector('1);
      write_dmcontrol(0, 1'b1, 1'b1);
      @(posedge clk);
      #1ns;
      if (!ndmreset) begin
        $fatal(1, "singleton ndmreset did not assert");
      end
      expect_halted_vector('0);
      expect_resume_ack_vector('0);
      write_dmcontrol(0, 1'b0, 1'b0);
      if (ndmreset) begin
        $fatal(1, "singleton ndmreset did not deassert");
      end
      expect_halted_vector('0);
      expect_resume_ack_vector('0);
    end else if (NrHarts == 4) begin
      // Power-of-two hart selection must preserve an unrelated stale
      // acknowledgement and support same-edge clear/ack traffic
      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(HaltedAddr, LastHart);
      write_debug_memory(ResumingAddr, 0);
      write_debug_memory(ResumingAddr, LastHart);
      expect_resume_ack(0, 1'b1);
      expect_resume_ack(LastHart, 1'b1);

      write_debug_memory(HaltedAddr, 0);
      write_dmcontrol(0, 1'b1, 1'b0);
      expect_resume_request(0, 1'b1);
      expect_resume_ack(0, 1'b0);
      expect_resume_ack(LastHart, 1'b1);

      write_debug_memory(ResumingAddr, 0);
      expect_resume_ack(0, 1'b1);
      @(posedge clk);
      expect_resume_request(0, 1'b0);
      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(HaltedAddr, LastHart);
      write_dmcontrol(20'(LastHart), 1'b1, 1'b0);
      expect_resume_request(LastHart, 1'b1);
      expect_resume_ack(LastHart, 1'b0);
      expect_resume_ack(0, 1'b1);

      // Clear hart 0 while acknowledging hart 3 on the same edge.  The
      // cross-hart effects must remain independent
      write_dmcontrol_and_resuming(20'd0, 1'b1, 1'b0, LastHart);
      expect_resume_ack(0, 1'b0);
      expect_resume_ack(LastHart, 1'b1);
      expect_resume_request(0, 1'b1);
      write_debug_memory(ResumingAddr, 0);
      expect_resume_ack(0, 1'b1);
      @(posedge clk);
      expect_resume_request(0, 1'b0);

      // Set every halted bit so ndmreset must clear the complete vector
      write_debug_memory(HaltedAddr, 0);
      write_debug_memory(HaltedAddr, 1);
      write_debug_memory(HaltedAddr, 2);
      write_debug_memory(HaltedAddr, LastHart);
      expect_halted_vector('1);
      expected_resumeack_before_ndmreset = '0;
      expected_resumeack_before_ndmreset[0] = 1'b1;
      expected_resumeack_before_ndmreset[LastHart] = 1'b1;
      expect_resume_ack_vector(expected_resumeack_before_ndmreset);
      write_dmcontrol(0, 1'b1, 1'b1);
      @(posedge clk);
      #1ns;
      if (!ndmreset) begin
        $fatal(1, "four-hart ndmreset did not assert");
      end
      expect_halted_vector('0);
      expect_resume_ack_vector('0);
      write_dmcontrol(0, 1'b0, 1'b0);
      if (ndmreset) begin
        $fatal(1, "four-hart ndmreset did not deassert");
      end
      expect_halted_vector('0);
      expect_resume_ack_vector('0);
    end else begin
      $fatal(1, "unsupported NrHarts=%0d", NrHarts);
    end

    $display("tb_dm_top_multihart_resume: passed");
    $finish;
  end

  initial begin
    #5us;
    $fatal(1, "tb_dm_top_multihart_resume: timeout");
  end

endmodule
