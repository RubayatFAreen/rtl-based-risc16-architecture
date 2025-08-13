`ifndef MEM_DATA_REF_SVH
`define MEM_DATA_REF_SVH

class datamem #(int size = 1024);

    // -------------------- Storage --------------------------
    bit [15:0] mem_ref [size];          // main array (zero‑init on new)

    // Debug history — parallel arrays keep addr/data for each write
    bit [15:0] write_hist      [$];     // address log
    bit [15:0] write_data_hist [$];     // data log

    // -------------------- Constructor ----------------------
    function new();
        // initialise memory to 0 for deterministic behaviour
        foreach (mem_ref[i]) mem_ref[i] = 16'h0;
    endfunction

    // -------------------- Write ----------------------------
    // • Handles negative addresses by 2’s‑complement wrap‑around.
    // • Ignores out‑of‑range addresses (no fatal)
    // --------------------------------------------------------
    function void write_mem(bit [15:0] addr, bit [15:0] data);
        automatic int unsigned a = (addr[15]) ? size + addr : addr; // wrap if negative
        if (a < size) begin
            mem_ref[a] = data;
            write_hist.push_back(a);
            write_data_hist.push_back(data);
        end
    endfunction

    // -------------------- Read -----------------------------
    function bit [15:0] read_mem(bit [15:0] addr);
        automatic int unsigned a = (addr[15]) ? size + addr : addr;
        return (a < size) ? mem_ref[a] : 16'h0;
    endfunction

    // -------------------- Reset ----------------------------
    function void reset();
        foreach (mem_ref[i]) mem_ref[i] = 16'h0;
        write_hist.delete();
        write_data_hist.delete();
    endfunction

endclass

`endif // MEM_DATA_REF_SVH
