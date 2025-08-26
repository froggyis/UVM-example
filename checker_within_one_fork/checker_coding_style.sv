`timescale 1ns/1ps

// ============================================================================
//  AXI Write Checker (pure SystemVerilog, no SVA)
//    - CHECK1: Next-cycle WVALID after AW handshake
//    - CHECK2: AWADDR aligned to AWSIZE on AW handshake
//    - CHECK3: WDATA/WSTRB/WLAST stable while stalled (WVALID & !WREADY)
//    - CHECK4: WLAST only on final beat (assumes single outstanding burst)
// ============================================================================
module axi_write_checker_full #(
  parameter int ADDR_W   = 32,
  parameter int DATA_W   = 32,
  parameter int WSTRB_W  = DATA_W/8,
  parameter int AWLEN_W  = 8,
  parameter int AWSIZE_W = 3
)(
  input  logic                    clk,
  input  logic                    rst_n,

  // AW channel
  input  logic                    awvalid,
  input  logic                    awready,
  input  logic [ADDR_W-1:0]       awaddr,
  input  logic [AWLEN_W-1:0]      awlen,     // beats-1
  input  logic [AWSIZE_W-1:0]     awsize,    // bytes = 1<<awsize

  // W channel
  input  logic                    wvalid,
  input  logic                    wready,
  input  logic [DATA_W-1:0]       wdata,
  input  logic [WSTRB_W-1:0]      wstrb,
  input  logic                    wlast
);

  // Handshake helpers (4-state aware)
  function automatic bit aw_hs_now();
    return (awvalid === 1'b1) && (awready === 1'b1);
  endfunction
  function automatic bit w_hs_now();
    return (wvalid === 1'b1) && (wready === 1'b1);
  endfunction

  // Start all checkers after reset deasserts
  initial begin
    wait (rst_n === 1'b1);

    fork
      // ------------------------------------------------------------
      // CHECK1: Next-cycle WVALID after an AW handshake
      // ------------------------------------------------------------
      begin : CHECK1
        forever begin
          wait (aw_hs_now());     // handshake "now"
          @(posedge clk);         // next cycle
          if (wvalid !== 1'b1)
            $error("[%0t] AXI CHECK1: WVALID must be 1 on the cycle after AW handshake.", $time);
        end
      end

      // ------------------------------------------------------------
      // CHECK2: AWADDR alignment to AWSIZE on handshake
      //         Uses mask (bytes-1) for X-robustness
      // ------------------------------------------------------------
      begin : CHECK2
        logic [ADDR_W-1:0] mask;
        int unsigned bytes;
        forever begin
          wait (aw_hs_now());
          bytes = 1 << awsize;          // number of bytes per beat
          mask  = bytes - 1;            // low bits that must be zero
          if ( (awaddr & mask) != '0 )
            $error("[%0t] AXI CHECK2: Unaligned AWADDR (addr=0x%0h, bytes=%0d).",
                   $time, awaddr, bytes);
        end
      end

      // ------------------------------------------------------------
      // CHECK3: W channel stable while stalled (WVALID & !WREADY)
      // ------------------------------------------------------------
      begin : CHECK3
        logic [DATA_W-1:0]  d_hold;
        logic [WSTRB_W-1:0] s_hold;
        logic               l_hold;
        forever begin
          @(posedge clk);
          if (wvalid === 1'b1 && wready === 1'b0) begin
            d_hold = wdata;  s_hold = wstrb;  l_hold = wlast;
            while (wvalid === 1'b1 && wready === 1'b0) begin
              if (wdata !== d_hold || wstrb !== s_hold || wlast !== l_hold)
                $error("[%0t] AXI CHECK3: WDATA/WSTRB/WLAST changed while stalled.", $time);
              @(posedge clk);
            end
          end
        end
      end

      // ------------------------------------------------------------
      // CHECK4: WLAST only on the final beat (AWLEN+1 beats total)
      //         (Assumes a single outstanding write burst)
      // ------------------------------------------------------------
      begin : CHECK4
        int unsigned beats, i;
        forever begin
          wait (aw_hs_now());
          beats = awlen + 1;
          for (i = 1; i <= beats; i++) begin
            // wait for a W handshake
            do @(posedge clk); while (!w_hs_now());
            if (i < beats) begin
              if (wlast !== 1'b0)
                $error("[%0t] AXI CHECK4: WLAST asserted early at beat %0d/%0d.", $time, i, beats);
            end else begin
              if (wlast !== 1'b1)
                $error("[%0t] AXI CHECK4: WLAST missing on final beat %0d/%0d.", $time, i, beats);
            end
          end
        end
      end
    join_none
  end
endmodule


// ============================================================================
//  Testbench
// ============================================================================
module tb;
  // Parameters to match checker
  localparam int ADDR_W   = 32;
  localparam int DATA_W   = 32;
  localparam int WSTRB_W  = DATA_W/8;
  localparam int AWLEN_W  = 8;
  localparam int AWSIZE_W = 3;

  // Clock/Reset
  logic clk = 0;
  logic rst_n = 0;

  // AW/W signals
  logic                    awvalid, awready;
  logic [ADDR_W-1:0]       awaddr;
  logic [AWLEN_W-1:0]      awlen;
  logic [AWSIZE_W-1:0]     awsize;

  logic                    wvalid, wready, wlast;
  logic [DATA_W-1:0]       wdata;
  logic [WSTRB_W-1:0]      wstrb;

  // Clock gen
  always #5 clk = ~clk;

  // Instantiate checker
  axi_write_checker_full #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .WSTRB_W(WSTRB_W),
    .AWLEN_W(AWLEN_W), .AWSIZE_W(AWSIZE_W)
  ) u_chk (
    .clk(clk), .rst_n(rst_n),
    .awvalid(awvalid), .awready(awready),
    .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
    .wvalid(wvalid), .wready(wready),
    .wdata(wdata), .wstrb(wstrb), .wlast(wlast)
  );

  // Simple helpers
  task automatic drive_aw(input [ADDR_W-1:0] addr,
                          input [AWLEN_W-1:0] len,
                          input [AWSIZE_W-1:0] size);
    awaddr  <= addr;
    awlen   <= len;
    awsize  <= size;
    awvalid <= 1;
    @(posedge clk);           // handshake (awready is 1)
    awvalid <= 0;
  endtask

  task automatic drive_w_beat(input [DATA_W-1:0] data,
                              input [WSTRB_W-1:0] strb,
                              input bit last,
                              input int stall_cycles = 0,
                              input bit violate_stability = 0);
    // Start beat
    wdata  <= data;
    wstrb  <= strb;
    wlast  <= last;
    wvalid <= 1;

    // Optional stall phase with stable (or intentionally changing) signals
    if (stall_cycles > 0) begin
      wready <= 0;
      repeat (stall_cycles) begin
        @(posedge clk);
        if (violate_stability) begin
          // flip one bit during stall to trigger CHECK3 error
          wdata <= wdata ^ 32'h0000_0001;
        end
      end
    end

    // Perform handshake
    wready <= 1;
    @(posedge clk);           // handshake here
    // Deassert valid after a beat unless caller keeps burst going
    // (caller can set wvalid again before next posedge if needed)
  endtask

  // Stimulus
  initial begin
    // Defaults
    awvalid = 0; awready = 1;
    awaddr  = '0; awlen = '0; awsize = 3'd2;   // 4 bytes/beat
    wvalid  = 0; wready = 1; wlast = 0;
    wdata   = '0; wstrb = '1;

    // Reset
    repeat (2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // ============================================================
    // PASS #1: AW handshake -> next cycle WVALID = 1
    //          3-beat burst, WLAST on final beat
    // ============================================================
    $display("\n---- PASS #1: AW@t, WVALID next cycle, 3 beats ----");
    drive_aw(32'h0000_1000, 8'd2, 3'd2); // len=2 => 3 beats total
    // Next cycle after AW: ensure WVALID=1 (checker will look here)
    wvalid <= 1; wready <= 1; wlast <= 0; wdata <= 32'hAAAA_0001; wstrb <= 4'hF;
    @(posedge clk);  // beat 1 (WLAST=0)
    wdata <= 32'hAAAA_0002; wlast <= 0;
    @(posedge clk);  // beat 2
    wdata <= 32'hAAAA_0003; wlast <= 1;
    @(posedge clk);  // beat 3 (final)
    wvalid <= 0; wlast <= 0;

    // ============================================================
    // PASS #2: WVALID asserted *before* AW; remains 1 across AW
    //          Single-beat burst (len=0 => 1 beat)
    // ============================================================
    $display("\n---- PASS #2: WVALID ahead of AW, 1 beat ----");
    wvalid <= 1; wready <= 1; wlast <= 1; wdata <= 32'hBBBB_0001; wstrb <= 4'hF;
    @(posedge clk);
    drive_aw(32'h0000_2000, 8'd0, 3'd2);  // 1 beat
    @(posedge clk); // handshake of the single beat occurs here
    wvalid <= 0; wlast <= 0;

    // ============================================================
    // PASS #3: Stall with stable signals (no error on CHECK3)
    // ============================================================
    $display("\n---- PASS #3: Stall with stable W signals ----");
    drive_aw(32'h0000_3000, 8'd0, 3'd2);
    drive_w_beat(32'hCCCC_0001, 4'hF, /*last*/1, /*stall_cycles*/2, /*violate*/0);
    wvalid <= 0; wlast <= 0;

    // ============================================================
    // FAIL (CHECK1): Next cycle WVALID == 0 after AW
    // ============================================================
    $display("\n---- FAIL (CHECK1): AW@t, next cycle WVALID == 0 ----");
    drive_aw(32'h0000_4000, 8'd0, 3'd2);
    // Intentionally keep wvalid low on the next cycle -> should $error
    @(posedge clk);

    // ============================================================
    // FAIL (CHECK2): Unaligned AWADDR for size=4 bytes
    // ============================================================
    $display("\n---- FAIL (CHECK2): Unaligned AWADDR ----");
    drive_aw(32'h0000_5002, 8'd0, 3'd2);  // addr not 4-byte aligned

    // ============================================================
    // FAIL (CHECK3): Change WDATA during stall
    // ============================================================
    $display("\n---- FAIL (CHECK3): WDATA changes while stalled ----");
    drive_aw(32'h0000_6000, 8'd0, 3'd2);
    drive_w_beat(32'hDDDD_0001, 4'hF, /*last*/1, /*stall_cycles*/2, /*violate*/1);
    wvalid <= 0; wlast <= 0;

    // ============================================================
    // FAIL (CHECK4): WLAST asserted early (len=2 => 3 beats)
    // ============================================================
    $display("\n---- FAIL (CHECK4): Early WLAST before final beat ----");
    drive_aw(32'h0000_7000, 8'd2, 3'd2);  // 3 beats expected
    // Beat 1
    wvalid <= 1; wready <= 1; wlast <= 0; wdata <= 32'hEEEE_0001; wstrb <= 4'hF;
    @(posedge clk);
    // Beat 2 (incorrectly assert WLAST early)
    wlast <= 1; wdata <= 32'hEEEE_0002;
    @(posedge clk);
    // Beat 3 (should have been the only WLAST)
    wlast <= 0; wvalid <= 0;

    // Wrap up
    $display("\n---- Test done ----");
    #20 $finish;
  end
endmodule
