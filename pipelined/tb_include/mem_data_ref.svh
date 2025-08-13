`ifndef MEM_DATA_REF_SVH
`define MEM_DATA_REF_SVH

// Reference class for data memory
class datamem #(int size = 1024);

    // ---------------- Storage & debug history ----------------
    bit [15:0] mem_ref [size];   // memory array (zero-init in new)
    bit [15:0] write_hist      [$]; // addresses written (in order)
    bit [15:0] write_data_hist [$]; // data written     (in order)

    // ---------------- Constructor ----------------------------
    function new;
        // Clear memory so test results are deterministic
        foreach (mem_ref[i]) mem_ref[i] = 16'h0000;
        // Histories start empty
        write_hist.delete();
        write_data_hist.delete();
    endfunction

    // ---------------- Write to memory ------------------------
    //  Maps address into range [0..size-1] using modulo addressing.
    //  Pushes the (addr,data) pair to history for later debug.
    function void write_mem(input bit [15:0] addr, bit [15:0] data);
        automatic int unsigned a = addr % size;
        mem_ref[a] = data;
        write_hist.push_back(a[15:0]);
        write_data_hist.push_back(data);
    endfunction

    // ---------------- Read from memory -----------------------
    //  Same modulo mapping as write_mem to stay consistent.
    function bit [15:0] read_mem(bit [15:0] addr);
        automatic int unsigned a = addr % size;
        return mem_ref[a];
    endfunction

    // ---------------- Reset memory ---------------------------
    function void reset();
        foreach (mem_ref[i]) mem_ref[i] = 16'h0000;
        write_hist.delete();
        write_data_hist.delete();
    endfunction

endclass

`endif // MEM_DATA_REF_SVH
