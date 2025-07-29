// -----------------------------------------------------
// UVM Transaction, Sequence, Sequencer, Driver, Env
// -----------------------------------------------------
`timescale 1ns/1ps
import uvm_pkg::*; `include "uvm_macros.svh"

// ------------------ Transaction ---------------------
class bus_trans extends uvm_sequence_item;
  rand int data;

  `uvm_object_utils_begin(bus_trans)
    `uvm_field_int(data, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "bus_trans");
    super.new(name);
  endfunction
endclass

// ------------------ Sequence ------------------------
class flat_seq extends uvm_sequence #(bus_trans);
  `uvm_object_utils(flat_seq)

  function new(string name = "flat_seq");
    super.new(name);
  endfunction

  task body();
    uvm_sequence_item tmp;
    bus_trans req, rsp;
    tmp = create_item(bus_trans::get_type(), m_sequencer, "req");
    // create_item() return uvm_sequence_item object (base),
    // in this case, we still use base handle to its, then we need to access derived member
    // so we still need $cast() to perform downcasting
    `uvm_info("SEQ", $sformatf("tmp data type is %s", tmp.get_type_name()), UVM_LOW)
    void'($cast(req, tmp));
    start_item(req);
    req.randomize() with { data == 10; };
    //`uvm_info("SEQ", $sformatf("sent a item \n%s", req.sprint()), UVM_LOW)
    finish_item(req);
    get_response(tmp);
    void'($cast(rsp, tmp));
    //`uvm_info("SEQ", $sformatf("got a item \n%s", rsp.sprint()), UVM_LOW)
  endtask
endclass

// ------------------ Sequencer -----------------------
class sequencer extends uvm_sequencer #(bus_trans);
  `uvm_component_utils(sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

// ------------------ Driver --------------------------
class driver extends uvm_driver #(bus_trans);
  `uvm_component_utils(driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    uvm_sequence_item tmp;
    bus_trans req, rsp;
    seq_item_port.get_next_item(tmp);
    `uvm_info("DRV", $sformatf("tmp data type is %s", tmp.get_type_name()), UVM_LOW)
    void'($cast(req, tmp));
    //`uvm_info("DRV", $sformatf("got a item \n%s", req.sprint()), UVM_LOW)
    void'($cast(rsp, req.clone()));
    rsp.set_sequence_id(req.get_sequence_id());
    rsp.data += 100;
    seq_item_port.item_done(rsp);
    //`uvm_info("DRV", $sformatf("sent a item \n%s", rsp.sprint()), UVM_LOW)
  endtask
endclass

// ------------------ Environment ----------------------
class env extends uvm_env;
  `uvm_component_utils(env)

  sequencer sqr;
  driver drv;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = sequencer::type_id::create("sqr", this);
    drv = driver::type_id::create("drv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

// ------------------ Test -----------------------------
class test extends uvm_test;
  `uvm_component_utils(test)

  env m_env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_env = env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    flat_seq seq;
    phase.raise_objection(this);

    seq = flat_seq::type_id::create("seq");
    seq.start(m_env.sqr);

    phase.drop_objection(this);
  endtask
endclass

// ------------------ Top Module -----------------------
module top;
  initial begin
    run_test("test");
  end
endmodule
