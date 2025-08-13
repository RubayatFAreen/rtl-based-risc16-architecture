`ifndef MEM_REG_REF_SVH
`define MEM_REG_REF_SVH

class regfile;

    // ----------------------------------------------------
    //  Storage (index 0 is constant‑zero in ISA spec)
    // ----------------------------------------------------
    bit [15:0] mem_ref [8];

    // Optional write history for debug (addr & data)
    bit [2:0]   wr_addr_hist [$];
    bit [15:0]  wr_data_hist [$];

    // ----------------------------------------------------
    //  Constructor — zero‑initialise
    // ----------------------------------------------------
    function new();
        reset();
    endfunction

    // ----------------------------------------------------
    //  Write — ignore attempts to write register 0
    // ----------------------------------------------------
    function void write_reg(bit [2:0] addr, bit [15:0] data);
        if (addr != 3'd0) begin
            mem_ref[addr] = data;
            wr_addr_hist.push_back(addr);
            wr_data_hist.push_back(data);
        end
    endfunction

    // ----------------------------------------------------
    //  Read — register 0 always returns zero
    // ----------------------------------------------------
    function bit [15:0] read_reg(bit [2:0] addr);
        return (addr == 3'd0) ? 16'h0 : mem_ref[addr];
    endfunction

    // ----------------------------------------------------
    //  Reset — clear registers 1‑7, keep r0 at 0
    // ----------------------------------------------------
    function void reset();
        foreach (mem_ref[i]) mem_ref[i] = 16'h0;
        wr_addr_hist.delete();
        wr_data_hist.delete();
    endfunction

endclass

`endif // MEM_REG_REF_SVH
