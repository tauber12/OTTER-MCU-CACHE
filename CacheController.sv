`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Cal Poly 
// Engineer:Alex Tauber
// 
// Create Date: 05/08/2025 01:18:05 PM
// Design Name: 
// Module Name:  512 byte 2-way set-associative cache with LRU, write-back, write-allocate. 
//               adapted for dualportram module and cachelineadapter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module CacheController(
    input CLK,
    input RESET,
    input MEM_READ,
    input MEM_WRITE,
    input [1:0] MEM_SIZE,
    input MEM_SIGN,
    input CACHELINEREADY, CACHELINEWRITTEN,
    input [31:0] DOUT2BYPASS,
    input [31:0] MEM_ADDR,
    input [31:0] MEMWRITE_DATA,
    input [255:0] CACHELINEIN,
  
    output logic ADAPTERRESET,
    output logic READ_MISS,
    output logic MEMORYWRITE,
    output logic [31:0] READWRITE_MISS_ADDR,
    output logic [31:0] WRITEBACK_ADDR,
    output logic [31:0] MEMREAD_DATA,
    output logic [255:0] CACHELINEOUT,
    output logic CACHEBUSY,
    output logic MEM_VALID
);

    typedef enum logic [2:0] 
    {IDLE, WRITEALLOCATE, WRITEMISS, READALLOCATE, READALLOCATEDONE, READMISS, WRITEBACK} cachestates_t;
    cachestates_t state, next_state;

    logic [2:0] setbits, offsetbitsword;
    logic [23:0] tagbits;

    logic [255:0] cachesets [0:7][0:1];
    logic [23:0] tags [0:7][0:1];
    logic validbits [0:7][0:1];
    logic dirtybits [0:7][0:1];
    logic lru [0:7];

    logic [255:0] cacheline, cachelinebuffer, currentcacheline;
    logic [31:0] word_out, new_word, old_word, memreaddata;
    logic [15:0] currenthword;
    logic [7:0] currentbyte;
    logic [3:0] setbitsbuffer, waybuffer;
    logic way0hit, way1hit, datahit, memsize, memsign, mmio_access, mmioaccessbuffer;
    
    // flags
    logic idle, read_allocate, read_allocatedone, write_allocate, write_back;

    // state registers for fsm
    always_ff @(posedge CLK) begin
        if (RESET) begin
        state <= IDLE;
        end else begin
        state <= next_state;
        end
    end

    // combinational signals (memaddr bit extraction, hit logic)
    always_comb begin
        memsize = MEM_SIZE;
        memsign = MEM_SIGN;
        setbits = MEM_ADDR[7:5];
        offsetbitsword = MEM_ADDR[4:2];
        tagbits = MEM_ADDR[31:8];
        way0hit = (tags[setbits][0] == tagbits) && validbits[setbits][0];
        way1hit = (tags[setbits][1] == tagbits) && validbits[setbits][1];
        datahit = way0hit || way1hit;  
        CACHEBUSY = (next_state != IDLE) || (state != IDLE);
        mmio_access = (MEM_ADDR >= 32'h11000000 && (MEM_READ || MEM_WRITE));
    end
    
    memoryREGISTER #(.n(1)) mmioaccess(mmio_access, CLK, RESET, 1'b1, mmioaccessbuffer);
    
    mux2to1 #(.n(32)) memreaddatamux
    (.in1(memreaddata), 
    .in2(DOUT2BYPASS),
    .sel(mmioaccessbuffer), 
    .out(MEMREAD_DATA));
    
    always_ff @(posedge CLK) begin
        if (RESET) begin //reset logic
            int i, j;
            for (i = 0; i < 8; i++) begin
                lru[i] <= 0;
                for (j = 0; j < 2; j++) begin
                    validbits[i][j] <= 0;
                    tags[i][j] <= 0;
                    cachesets[i][j] <= 0;
                    dirtybits[i][j] <= 0;
                end
            end
        end else begin
            if (idle && (!mmio_access)) begin
                MEM_VALID = validbits[setbits][~way0hit];
                if (MEM_READ && datahit) begin  
                     //assert valid @ way if read hit              
                    currentcacheline = way0hit ? cachesets[setbits][0] : cachesets[setbits][1];
                    word_out = currentcacheline[32*offsetbitsword +: 32];
                    case (MEM_SIZE)
                        2'b00: begin // byte
                        case (MEM_ADDR[1:0])
                            2'b00: currentbyte = word_out[7:0];
                            2'b01: currentbyte = word_out[15:8];
                            2'b10: currentbyte = word_out[23:16];
                            2'b11: currentbyte = word_out[31:24];
                        endcase 
                            memreaddata <= MEM_SIGN ? {{24{currentbyte[7]}}, currentbyte} : {24'b0, currentbyte}; //sign extend if necessary
                        end
                        2'b01: begin // halfword
                        case (MEM_ADDR[1])
                            1'b0: currenthword = word_out[15:0];
                            1'b1: currenthword = word_out[31:16];
                        endcase
                            memreaddata <= MEM_SIGN ? {{16{currenthword[15]}}, currenthword} : {16'b0, currenthword}; //sign extend if necessary
                        end
                        2'b10: begin // word
                            memreaddata <= word_out;
                        end
                    endcase
                    lru[setbits] <= way0hit ? 1 : 0;
                end else if (MEM_READ && !datahit) begin
                    memreaddata <= 32'hDEADBEEF;
                    READWRITE_MISS_ADDR <= {MEM_ADDR[31:5],5'b0};
                    setbitsbuffer <= setbits;
                    waybuffer <= lru[setbits];
                end else if (MEM_WRITE && datahit) begin               
                    if (way0hit) begin
                        old_word = cachesets[setbits][0][32*offsetbitsword +: 32];
                        case (MEM_SIZE)
                            2'b00: begin // store byte
                                case (MEM_ADDR[1:0])
                                    2'b00: new_word = {old_word[31:8], MEMWRITE_DATA[7:0]};
                                    2'b01: new_word = {old_word[31:16], MEMWRITE_DATA[7:0], old_word[7:0]};
                                    2'b10: new_word = {old_word[31:24], MEMWRITE_DATA[7:0], old_word[15:0]};
                                    2'b11: new_word = {MEMWRITE_DATA[7:0], old_word[23:0]};
                                endcase
                            end
                            2'b01: begin // store halfword
                                case (MEM_ADDR[1])
                                    1'b0: new_word = {old_word[31:16], MEMWRITE_DATA[15:0]};
                                    1'b1: new_word = {MEMWRITE_DATA[15:0], old_word[15:0]};
                                endcase
                            end
                            2'b10: begin // store word
                                new_word = MEMWRITE_DATA;
                            end
                        endcase
                        cachesets[setbits][0][32*offsetbitsword +: 32] <= new_word;
                        dirtybits[setbits][0] <= 1;
                    end else if (way1hit) begin
                        old_word = cachesets[setbits][1][32*offsetbitsword +: 32];
                        case (MEM_SIZE)
                            2'b00: begin // store byte
                                case (MEM_ADDR[1:0])
                                    2'b00: new_word = {old_word[31:8], MEMWRITE_DATA[7:0]};
                                    2'b01: new_word = {old_word[31:16], MEMWRITE_DATA[7:0], old_word[7:0]};
                                    2'b10: new_word = {old_word[31:24], MEMWRITE_DATA[7:0], old_word[15:0]};
                                    2'b11: new_word = {MEMWRITE_DATA[7:0], old_word[23:0]};
                                endcase
                            end
                            2'b01: begin // store halfword
                                case (MEM_ADDR[1])
                                    1'b0: new_word = {old_word[31:16], MEMWRITE_DATA[15:0]};
                                    1'b1: new_word = {MEMWRITE_DATA[15:0], old_word[15:0]};
                                endcase
                            end
                            2'b10: begin // store word
                                new_word = MEMWRITE_DATA;
                            end
                        endcase
                        cachesets[setbits][1][32*offsetbitsword +: 32] <= new_word;
                        dirtybits[setbits][1] <= 1;
                    end 
                end else if (MEM_WRITE && !datahit) begin
                    memreaddata <= 32'hDEADBEEF;
                    READWRITE_MISS_ADDR <= {MEM_ADDR[31:5],5'b0};
                    setbitsbuffer <= setbits;
                    waybuffer <= lru[setbits];
                end
            end else if (read_allocate) begin
                tags[setbitsbuffer][waybuffer] <= READWRITE_MISS_ADDR[31:8];
                cachesets[setbitsbuffer][waybuffer] <= CACHELINEIN;
                validbits[setbitsbuffer][waybuffer] <= 1;
                CACHELINEOUT <= cachelinebuffer;
            end else if (read_allocatedone) begin
                lru[setbitsbuffer] <= ~lru[setbitsbuffer]; //update lru bit 
            end
            else if (write_allocate) begin
                cacheline = CACHELINEIN;
                cacheline[32*offsetbitsword+:32] = MEMWRITE_DATA;
                tags[setbitsbuffer][waybuffer] <= READWRITE_MISS_ADDR[31:8];
                cachesets[setbitsbuffer][waybuffer] <= cacheline;
                CACHELINEOUT <= cachelinebuffer;
                validbits[setbitsbuffer][waybuffer] <= 1;
                dirtybits[setbitsbuffer][waybuffer] <= 1;
                lru[setbitsbuffer] <= ~lru[setbitsbuffer];
            end          
        end        
    end

    // FSM transition logic
    always_comb begin
        idle = 0; read_allocate = 0; cachelinebuffer = 0;
        read_allocatedone = 0; write_back = 0; write_allocate = 0;
        ADAPTERRESET = 0; READ_MISS = 0; MEMORYWRITE = 0;
        next_state = state;

        case (state)
            IDLE: begin
                idle = 1;
                if (MEM_READ && !datahit && !mmio_access) begin
                    READ_MISS = 1;
                    ADAPTERRESET = 1;
                    next_state = READMISS;
                end else if (MEM_WRITE && !datahit && !mmio_access) begin
                    ADAPTERRESET = 1;
                    next_state = WRITEMISS;
                end
            end
            READMISS: begin
                READ_MISS = 1;
                if (CACHELINEREADY) begin
                    READ_MISS = 0;
                    next_state = READALLOCATE;
                end
            end
            READALLOCATE: begin
                read_allocate = 1;
                cachelinebuffer = cachesets[setbits][lru[setbits]];
                if (dirtybits[setbits][lru[setbits]]) begin
                    next_state = WRITEBACK;
                    WRITEBACK_ADDR = {tags[setbits][lru[setbits]], setbits, 5'b0};
                end
                else next_state = READALLOCATEDONE;
            end
            READALLOCATEDONE: begin
                read_allocatedone = 1;
                next_state = IDLE;
            end
            WRITEBACK: begin
                MEMORYWRITE = 1;
                if (CACHELINEWRITTEN) next_state = IDLE;
            end
            WRITEMISS: begin
                READ_MISS = 1;
                if (CACHELINEREADY) next_state = WRITEALLOCATE;
            end
            WRITEALLOCATE: begin
                write_allocate = 1;
                cachelinebuffer = cachesets[setbits][lru[setbits]];
                if (dirtybits[setbits][lru[setbits]]) begin
                    next_state = WRITEBACK;
                    WRITEBACK_ADDR = {tags[setbits][lru[setbits]], setbits, 5'b0};
                end
                else next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

endmodule
