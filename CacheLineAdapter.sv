`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Cal Poly
// Engineer: Alex Tauber
// 
// Create Date: 04/07/2024 12:16:02 AM
// Design Name: 
// Module Name: CacheLineAdapter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description:
//         This module is responsible for interfacing between the cache and the memory. The middle man if you will.
//         It will be responsible for reading and writing to the memory
//         It will also be responsible for reading and writing to the cache
//         It will be responsible for the cache line size
// 
// Instantiated by:
//      CacheLineAdapter myCacheLineAdapter (
//          .CLK        ()
//      );
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module CacheLineAdapter (
    input CLK,
    input RESET,
    input READING,
    input WRITING,
    input [31:0] READWRITE_MISS_ADDR,
    input [31:0] WRITEBACK_ADDR,
    input [31:0] MEMDATA_IN, //from main memory
    input [255:0] CACHELINEIN,
    output logic READ_ENABLE,
    output logic WRITE_ENABLE, 
    output logic [31:0] ADDR,
    output logic [31:0] DOUT,
    output logic [255:0] CACHELINEOUT,
    output logic CACHELINEREADY, CACHELINEWRITTEN
    
    );
    
    logic [255:0] cacheline;
    logic [3:0] wordcntrd, wordcntwr;
    logic busy, writebusy, cachelineready, cachelinewritten;
    
    assign READ_ENABLE = READING;
    assign WRITE_ENABLE = WRITING;
    assign cachelinebusy = busy;
    assign CACHELINEREADY = cachelineready;
    assign CACHELINEWRITTEN = cachelinewritten;
    //assign ADDR = READWRITE_MISS_ADDR + wordcntrd;
    
    //addr selection mux for reading or writing
    mux2to1 #(.n(32)) addrmux
    (.in1((READWRITE_MISS_ADDR + wordcntrd*4)), 
    .in2((WRITEBACK_ADDR + wordcntwr*4)),
    .sel(WRITING), 
    .out(ADDR));

    //counter for retrieving 8 words for cacheline (missed reads/writes)
    always_ff @(posedge CLK or posedge RESET) begin
        if(cachelineready)begin
            CACHELINEOUT = cacheline;
        end
            cachelineready <= 0; 
        if (RESET) begin
            wordcntrd   <= 0;
            cacheline <= 256'd0;
            busy      <= 0;
        end else begin  
        if(READING)begin
            if (!busy && !cachelineready) begin
                busy    <= 1;
                wordcntrd <= 1;             
            end
            else if (busy) begin
                cacheline[32*(wordcntrd-1) +: 32] = MEMDATA_IN;
            if (wordcntrd == 4'd8) begin
                wordcntrd <= 0;
                cachelineready <= 1;
                busy <= 0;                 
            end else begin
                wordcntrd <= wordcntrd + 1;
            end
            end         
        end
        end
    end
    
    logic [2:0] internal_cnt;

    always_ff @(posedge CLK or posedge RESET) begin
        cachelinewritten <= 0;
        DOUT <= 0;  
        if (RESET) begin
            wordcntwr     <= 0;
            internal_cnt  <= 0;
            writebusy     <= 0;
        end else if (WRITING) begin
            if (!writebusy) begin
                writebusy     <= 1;
                internal_cnt  <= 0;
                wordcntwr     <= 0;
            end else begin
                // output current word
                DOUT <= CACHELINEIN[32*internal_cnt +: 32];
                // update wordcntwr with a one-cycle delay
                if (internal_cnt == 3'd1) begin
                    wordcntwr <= 1;
                end else if (internal_cnt > 3'd1) begin
                    wordcntwr <= wordcntwr + 1;
                end
    
                if (internal_cnt == 3'd7) begin
                    DOUT <= CACHELINEIN[32*internal_cnt +: 32];
                    cachelinewritten <= 1;
                    writebusy        <= 0;
                    wordcntwr        <= 7;
                end
                // advance internal counter
                internal_cnt <= internal_cnt + 1;
            end
        end
    end

endmodule
