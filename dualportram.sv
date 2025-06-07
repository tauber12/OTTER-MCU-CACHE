`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Alex Tauber
// 
// Create Date: 06/01/2025 04:53:55 PM
// Design Name: 
// Module Name: dualportram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: this is a simplified otter memory module 
// with all complex processing responsibilities moved to cache
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
/////////////////////////////////////////// ///////////////////////////////////////


module dualportram#(
    parameter ACTUAL_WIDTH = 14 //16 x 32-bit words (32KB)
)(
    input CLK,
    input READ1,
    input READ2,   
    input WRITE2,
    input MMIOREAD,
    input MMIOWRITE,
    input [31:0] ADDR1,
    input [31:0] ADDR2,
    input [31:0] ADDR2BYPASS, 
    input [31:0] DIN2,
    input [31:0] MMIO_IN,
    
    output logic MMIO_WR,
    output logic [31:0] DOUT1,
    output logic [31:0] DOUT2,
    output logic [31:0] DOUT2BYPASS  
 );
 
    localparam DEPTH = 2**ACTUAL_WIDTH;
    localparam MMIO_BASE = 32'h11000000;
    
    (* rom_style="{distributed | block}" *) 
    (* ram_decomp = "power" *)
     
    logic [31:0] memory [0:DEPTH-1]; //memory array
    
    wire [ACTUAL_WIDTH-1:0] addr1 = ADDR1[ACTUAL_WIDTH+1:2];
    wire [ACTUAL_WIDTH-1:0] addr2 = ADDR2[ACTUAL_WIDTH+1:2];
    
    initial begin
        $readmemh("otter_memory.mem", memory, 0, DEPTH-1);
    end

    // instruction port (read-only)
    always_ff @(posedge CLK) begin
        if (READ1)
            DOUT1 <= memory[addr1];
    end

    // data port (read/write)
    always_ff @(posedge CLK) begin
        MMIO_WR = 0;
        if (ADDR2BYPASS >= MMIO_BASE) begin
            if (MMIOWRITE) begin             
                MMIO_WR = 1;
            end else begin
                MMIO_WR = 0;
            end
            if (MMIOREAD) begin
                DOUT2BYPASS <= MMIO_IN;
            end
        end 
        else begin
            if (READ2)
                DOUT2 <= memory[addr2];
            if (WRITE2)
                memory[addr2] <= DIN2;
        end
    end
   
    
endmodule
