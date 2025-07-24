// -----------------------------------------------------------------------------
//  vcs_axi_uvm_demo.sv  –  4‑instance AXI‑like interface wired by genvar loop
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
import uvm_pkg::*;
`include "uvm_macros.svh"

// 1) Two‑signal AXI‑lite‑style interface
interface axi_if #(int WIDTH = 32) (input logic clk);
  logic              valid;
  logic [WIDTH-1:0]  data;
endinterface

// 2) Driver
class axi_driver extends uvm_component;
  virtual axi_if vif;
  `uvm_component_utils(axi_driver)

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (! uvm_config_db#(virtual axi_if)::get(this,"","vif",vif))
      `uvm_fatal("NOVIF", "virtual interface not supplied")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);
      vif.data  <= $urandom;
      vif.valid <= 1;
      @(posedge vif.clk);
      vif.valid <= 0;
    end
  endtask
endclass

// 3) Environment – 4 drivers
class axi_env extends uvm_env;
  axi_driver drv[4];
  `uvm_component_utils(axi_env)

  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (drv[i])
      drv[i] = axi_driver::type_id::create($sformatf("drv[%0d]",i), this);
  endfunction
endclass

// 4) Test
class base_test extends uvm_test;
  axi_env m_env;
  `uvm_component_utils(base_test)

  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = axi_env::type_id::create("m_env", this);
  endfunction
endclass

// 5) Top‑level
module tb;
  // clock
  logic clk = 0; always #5 clk = ~clk;

  // ---- array of four interface *instances* ---------------------------------
  axi_if #(32) axi[4] (.clk(clk));   // axi[0] … axi[3]

  // ---- genvar loop: constant index -> legal cross‑module reference ----------
  genvar gi;
  generate
    for (gi = 0; gi < 4; gi++) begin : CFG
      initial begin
        string path;
        path = $sformatf("uvm_test_top.m_env.drv[%0d]", gi);
        // gi is a *genvar* → constant when this initial is elaborated
        uvm_config_db#(virtual axi_if)::set(null, path, "vif", axi[gi]);
      end
    end
  endgenerate

  // ---- kick off UVM ---------------------------------------------------------
  initial run_test("base_test");
endmodule
// -----------------------------------------------------------------------------