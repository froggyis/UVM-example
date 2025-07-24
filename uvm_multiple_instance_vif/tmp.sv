//----------------------------------------------------------------------------
//  runtime_string_hdl_connect_demo.sv     (NO genvar, uses string + DPI)
//----------------------------------------------------------------------------
`timescale 1ns/1ps

// 1) Bring in UVM first
import uvm_pkg::*;             `include "uvm_macros.svh"

// 2) Bring in the DPI header that DEFINES uvm_hdl_path_pkg
`include "uvm_hdl.svh"         // make sure your +incdir paths can find this

//---------------------------------------------------------------------------
//  3) Tiny AXI‑like interface (two signals)
//---------------------------------------------------------------------------
interface axi_if #(int W = 32) (input logic clk);
  logic         valid;
  logic [W-1:0] data;
endinterface



//---------------------------------------------------------------------------
//  4) Driver – fetches STRING path from config_db, converts with DPI
//---------------------------------------------------------------------------
class axi_driver extends uvm_component;
  virtual axi_if vif;                 // will be bound at run time
  `uvm_component_utils(axi_driver)

  function new(string n, uvm_component p); super.new(n,p); endfunction

  function void build_phase(uvm_phase phase);
    string path;
    if (!uvm_config_db#(string)::get(this,"","vif_path", path))
      `uvm_fatal("NOPATH", "vif_path not set")

    import uvm_hdl_path_pkg::*;       // bring DPI funcs into scope here
    if (!uvm_hdl_connect(path, vif))
      `uvm_fatal("CONNECT", $sformatf("uvm_hdl_connect failed for %s", path));
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);  vif.data <= $urandom;  vif.valid <= 1;
      @(posedge vif.clk);  vif.valid <= 0;
    end
  endtask
endclass



//---------------------------------------------------------------------------
//  5) Environment and Test (minimal scaffolding)
//---------------------------------------------------------------------------
class axi_env extends uvm_env;
  axi_driver drv[4];
  `uvm_component_utils(axi_env)

  function new(string n, uvm_component p); super.new(n,p); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    foreach (drv[i])
      drv[i] = axi_driver::type_id::create($sformatf("drv[%0d]", i), this);
  endfunction
endclass

class base_test extends uvm_test;
  axi_env m_env;
  `uvm_component_utils(base_test)

  function new(string n, uvm_component p); super.new(n,p); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = axi_env::type_id::create("m_env", this);
  endfunction
endclass



//---------------------------------------------------------------------------
//  6) Top‑level – run‑time FOR loop, only STRINGS cross hierarchy
//---------------------------------------------------------------------------
module tb;
  logic clk = 0; always #5 clk = ~clk;

  // physical interface array (constant‑index only in HDL references)
  axi_if #(32) axi[4] (.clk(clk));

  initial begin
    for (int i = 0; i < 4; i++) begin
      string drv_path = $sformatf("uvm_test_top.m_env.drv[%0d]", i);
      string if_path  = $sformatf("tb.axi[%0d]", i);  // just TEXT → OK

      // save ONLY the string into the DB
      uvm_config_db#(string)::set(null, drv_path, "vif_path", if_path);
    end
    run_test("base_test");
  end
endmodule
//----------------------------------------------------------------------------
