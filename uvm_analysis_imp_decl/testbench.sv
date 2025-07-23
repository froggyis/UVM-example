
`include "uvm_macros.svh"
`include "my_testbench_pkg.svh"

// The top module that contains the DUT and interface.
// This module starts the test.


module top;
  import uvm_pkg::*;
  import my_testbench_pkg::*;
  initial begin
    run_test("my_test");
  end
endmodule
