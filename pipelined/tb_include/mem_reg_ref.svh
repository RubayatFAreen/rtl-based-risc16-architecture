`ifndef MEM_REG_REF_SVH
`define MEM_REG_REF_SVH

// Reference class for the register file
class regfile;

    // ---------------- Storage (r0..r7) ----------------
    bit [15:0] mem_ref [7:0];

    // Optional write history for debug
    bit [2:0]   wr_addr_hist [$];
    bit [15:0]  wr_data_hist [$];

    // ---------------- Constructor ---------------------
    function new;
        reset(); // zero-initialize and clear histories
    endfunction

    // ---------------- Write helper --------------------
    // Writes are ignored for r0 (addr==0), per ISA.
    function void write_reg(bit [2:0] addr, bit [15:0] data);
        if (addr != 3'd0) begin
            mem_ref[addr] = data;
            wr_addr_hist.push_back(addr);
            wr_data_hist.push_back(data);
        end
    endfunction

    // ---------------- Read helper ---------------------
    // r0 always reads as 0; others return stored value.
    function bit [15:0] read_reg(bit [2:0] addr);
        return (addr == 3'd0) ? 16'h0000 : mem_ref[addr];
    endfunction

    // ---------------- Reset model ---------------------
    function void reset();
        foreach (mem_ref[i]) mem_ref[i] = 16'h0000;
        wr_addr_hist.delete();
        wr_data_hist.delete();
    endfunction

endclass

`endif // MEM_REG_REF_SVH
