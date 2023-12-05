/*
* OQPSK Raised Cosine modulator
* LALR - 2022
*
*/

//----------------------------------------------------------------------
// TOP
module OQPSK_RCOSINE_ALL #(parameter
	DW_IN 			= 13, 	// Output bits
	I_SEL 			= 01,		// Integer bits
	SAMPLES 			= 02,		// Samples per symbol
	PS_SMPLS			= 50,		// Samples of the pulse shaping
	ADDR_WIDTH 		= 2, 
	DATA_WIDTH_MEM = 16,
	INIT_I 			= 0,		// Init value for Inphase counter
	INIT_Q 			= 25,		// Init value for In-quadrature counter
	NUM_BITS_1 		= 2,		// Number of bits of the first latch
	NUM_M_C 			= 2		// Number of inputs of muller C cell
) (

`ifdef USE_POWER_PINS
    inout vdd,	// User area 1 1.8V supply
    inout vss,	// User area 1 digital ground
`endif
	input RST,
	input EN,
	input REQ_SAMPLE,
	input ACK,
	input Bit_In,
	output signed [(DW_IN-I_SEL):I_SEL-1] I,
	output signed [(DW_IN-I_SEL):I_SEL-1] Q,
	output [5:0] addI,
	output [5:0] addQ,
	output [37:0] io_oeb	
);	
assign io_oeb[8:0] = {12{1'b1}};
assign io_oeb[37:9] = {26{1'b0}};



	wire [1:0] symbol;
	wire [1:0] bit_I_dr, bit_Q_dr,bit_Q_delay;
	wire [$clog2(PS_SMPLS)-1:0] count_rom_I, count_rom_Q;

	
	// Symbol generation
	gen_sym_1 gen_sym(
		.reset		(RST),
		.bit_in		(Bit_In),
		.enable		(EN),	
		.signal_i	((count_rom_I == 49)?1'b1:1'b0),
		.signal_q	((count_rom_Q == 49)?1'b1:1'b0),
		.out_sym	(symbol)
	);
	
	
	// Dual-rail - 4 phases conversion
	mapper_dr mapper(
		.in_sym		(symbol),
		.ack			(ACK),
		.bit_I		(bit_I_dr),
		.bit_Q		(bit_Q_dr)
	);	


	// Registar/Latch dual rail
	reg_async #(NUM_BITS_1) reg_latch(
		.reset		(RST),
		.enable		((count_rom_Q == 49)?1'b1:1'b0), 
		.data_in		(bit_Q_dr),
		.data_out	(bit_Q_delay)
	);
	
	// Pulse shaping filter	
	p_shaping_dr #(DW_IN, I_SEL, SAMPLES, PS_SMPLS, INIT_I) p_shaping_I (
		.reset		(RST),
		.bit_in_dr	(bit_I_dr),
		.enable		(EN),
		.signal_req (REQ_SAMPLE),
		.count		(count_rom_I),
		.out_qpsk	(I)
	);

	p_shaping_dr #(DW_IN, I_SEL, SAMPLES, PS_SMPLS, INIT_Q) p_shaping_Q (
		.reset		(RST),
		.bit_in_dr	(bit_Q_delay),
		.enable		(EN),
		.signal_req (REQ_SAMPLE),		
		.count		(count_rom_Q),		
		.out_qpsk	(Q)
	);	

	assign addI = count_rom_I;
	assign addQ = count_rom_Q;	
	
endmodule

//------------------------------------------------------
module gen_sym_1 (
	input reset,
	input bit_in,
	input enable,
	input signal_i,
	input signal_q,
	output [1:0] out_sym
);

wire bit_2M;


reg_async #(1) Reg_2M(
	.reset(reset),
	.enable(signal_i ^ signal_q), 
	.data_in((enable == 1)?bit_in:1'b0),
	.data_out(bit_2M)
);

reg_async #(2) Reg_Sym(
	.reset(reset),
	.enable(signal_i), 
	.data_in({bit_2M,(enable == 1)?bit_in:1'b0}),
	.data_out(out_sym)
);


endmodule


//------------------------------------------------------
module reg_async #(parameter SIZE = 2)(
	input reset,
	input enable, 
	input [SIZE-1:0] data_in,
	output reg [SIZE-1:0] data_out
);

always @(posedge enable or negedge reset) begin
	if(!reset)
		data_out = 0;
	else begin
		if (enable)
			data_out = data_in;
	end
		

end

endmodule


//----------------------------------------------------
module mapper_dr(
	input [1:0] in_sym,
	input ack,
	output [1:0] bit_I,
	output [1:0] bit_Q
);

 wire [1:0] bit_I_dr,bit_Q_dr;

 assign bit_I_dr = (in_sym[1] == 1'b1)?2'b10:2'b01; //SI EL SIMBOLO APARECE AL REVES 
 assign bit_Q_dr = (in_sym[0] == 1'b1)?2'b10:2'b01; //CAMBIAR AQUI
 
assign bit_I = (!ack)?bit_I_dr:2'b00;  
										   			
assign bit_Q = (!ack)?bit_Q_dr:2'b00;	
	
endmodule


//--------------------------------------------------
module p_shaping_dr #(parameter 
DW_IN 	= 13, 	// Output bits
I_SEL 	= 01,	// Integer bits
SAMPLES 	= 02,	// Samples per symbol
PS_SMPLS	= 50, // Samples of the pulse shaping
INIT 		= 0	// Initial counter
)(

input 	reset,
input 	[1:0] bit_in_dr,
input		enable,
input 	signal_req,
output 	[$clog2(PS_SMPLS)-1:0] count,
output signed [I_SEL-1:-(DW_IN-I_SEL)] out_qpsk	    	//component
);



	wire [DW_IN-2:0] data_rom_tmp;
	wire [DW_IN-1:0] data_rom_c;
	wire [$clog2(PS_SMPLS)-1:0] counter_tmp;
	reg  ctl,ctl_mux;
	
counter #(PS_SMPLS,INIT) counter_rom (
	.reset(reset),
	.enable(enable),
	.signal_count(signal_req),
	.count(counter_tmp)
);

	pulse_shaping_v1 #(.SAMPLES(PS_SMPLS), .DW(DW_IN), .I(I_SEL-1)) p_shaping_I(
		.reset(reset),
		.counter_addr(counter_tmp),
		.bit_in(bit_in_dr[1]),
		.out_filtered_s(out_qpsk)
	);


	
assign count = counter_tmp;


endmodule


//-----------------------------------------------------
module counter #(parameter SAMPLES = 50, INIT=0)(
	input reset,
	input enable,
	input signal_count,
	output [$clog2(SAMPLES)-1:0] count
);



	reg [$clog2(SAMPLES-1)-1:0] counter;

	always @(posedge signal_count or negedge reset) begin
		if(!reset) 
			counter = INIT;
		else
			if(enable) begin
				if(signal_count) begin
					if (counter == 49) 
						counter = 0;
					else
						counter = counter + 1'b1;
				end
			end
		end
		
	assign count = counter;	
		
		
endmodule

//----------------------------------------------------
module pulse_shaping_v1 #(parameter SAMPLES=50, DW=13, I=0)
(	input reset,
	input [$clog2(SAMPLES)-1:0] counter_addr,
	input bit_in,
	output signed [I-1:-(DW-I)] out_filtered_s
);

// `include "MathFun.vh"

wire signed[I-1:-(DW-I)] o_rom_1, o_rom_2, o_rom_3;
reg signed[I-1:-(DW-I)] o_rom_1_1, o_rom_2_1, o_rom_3_1;
reg bit_in_0;
reg bit_in_1;
reg bit_in_2;
reg ctl;
reg ctl_1;
reg [1:0] counter = 2'b00;

	always @(*) begin
		if (!reset) begin
			ctl = 1'b0;
			ctl_1 = bit_in;
			bit_in_0 = 1'b0;
		end
		else
			bit_in_0 = bit_in;
			if (counter_addr == 6'd49) begin				
				ctl = 1'b1;
							
				if (bit_in_0 == ctl_1) begin
					o_rom_2_1 = (bit_in_1 == 1'b1)?o_rom_2:-o_rom_2;
					ctl_1 = bit_in_1;
				end
				else begin
					o_rom_2_1 = (bit_in_1 == 1'b1)?-o_rom_2:o_rom_2;
					ctl_1 = bit_in_1;
				end
				
			end
			else begin
				ctl = 1'b0;
				o_rom_2_1 = (bit_in_1 == 1'b1)?o_rom_2:-o_rom_2;
			end
						
			
			o_rom_1_1 = (bit_in == 1'b1)?o_rom_1:-o_rom_1;			

			o_rom_3_1 = (bit_in_2 == 1'b1)?o_rom_3:-o_rom_3;
		end

  always @ (posedge ctl or negedge reset) begin
	  if(!reset) begin
				bit_in_1 <= 1'b0;
				bit_in_2 <= 1'b0;
				counter <= 2'b00;
	  end
	  else begin
		 counter <= (counter <= 2'b01)?counter + 1'b1:counter;		 
		 bit_in_1 <= bit_in;
		 bit_in_2 <= bit_in_1;
	  end
  end	

rcosine_1 #(SAMPLES,DW,I) rcos_1
(
	.addr(counter_addr),
	.out(o_rom_1) 
);

rcosine_2 #(SAMPLES,DW,I) rcos_2
(
	.addr(counter_addr),
	.out(o_rom_2) 
);

rcosine_3 #(SAMPLES,DW,I) rcos_3
(
	.addr(counter_addr),
	.out(o_rom_3) 
);


assign out_filtered_s = o_rom_1_1 + ((counter > 2'b00)?o_rom_2_1:0) + ((counter > 2'b01)?o_rom_3_1:0);
endmodule


//----------------------------------------------------------------------
module rcosine_1 #(parameter SAMPLES=50, DW=13, I=0)
(
input	[$clog2(SAMPLES)-1:0] addr, 
output reg signed[I-1:-(DW-I)] out
);
	always@*
	case(addr)
				00:out = 13'b0000000000000;
				01:out = 13'b0000000000000;
				02:out = 13'b0000000000010;
				03:out = 13'b0000000000100;
				04:out = 13'b0000000001000;
				05:out = 13'b0000000001100;
				06:out = 13'b0000000010010;
				07:out = 13'b0000000011000;
				08:out = 13'b0000000100000;
				09:out = 13'b0000000101000;
				10:out = 13'b0000000110000;
				11:out = 13'b0000000111001;
				12:out = 13'b0000001000001;
				13:out = 13'b0000001001001;
				14:out = 13'b0000001010000;
				15:out = 13'b0000001010111;
				16:out = 13'b0000001011011;
				17:out = 13'b0000001011101;
				18:out = 13'b0000001011110;
				19:out = 13'b0000001011011;
				20:out = 13'b0000001010101;
				21:out = 13'b0000001001100;
				22:out = 13'b0000000111111;
				23:out = 13'b0000000101110;
				24:out = 13'b0000000011001;
				25:out = 13'b0000000000000;
				26:out = -13'b0000000011101;
				27:out = -13'b0000000111101;
				28:out = -13'b0000001100001;
				29:out = -13'b0000010001001;
				30:out = -13'b0000010110010;
				31:out = -13'b0000011011101;
				32:out = -13'b0000100001010;
				33:out = -13'b0000100110110;
				34:out = -13'b0000101100010;
				35:out = -13'b0000110001100;
				36:out = -13'b0000110110011;
				37:out = -13'b0000111010101;
				38:out = -13'b0000111110010;
				39:out = -13'b0001000001000;
				40:out = -13'b0001000010110;
				41:out = -13'b0001000011011;
				42:out = -13'b0001000010101;
				43:out = -13'b0001000000100;
				44:out = -13'b0000111100110;
				45:out = -13'b0000110111010;
				46:out = -13'b0000110000000;
				47:out = -13'b0000100110111;
				48:out = -13'b0000011011111;
				49:out = -13'b0000001110111;
	default: out = 13'b0000000000000;
	endcase
//			`include "MathFun.vh"
endmodule


//------------------------------------------
module rcosine_2 #(parameter SAMPLES=50, DW=13, I=0)
(
input	[$clog2(SAMPLES)-1:0] addr, 
output reg signed[I-1:-(DW-I)] out
);
	always@*
	case(addr)
			00:out = 13'b0000000000000;
			01:out = 13'b0000010000110;
			02:out = 13'b0000100011011;
			03:out = 13'b0000110111110;
			04:out = 13'b0001001101110;
			05:out = 13'b0001100101010;
			06:out = 13'b0001111110000;
			07:out = 13'b0010010111111;
			08:out = 13'b0010110010101;
			09:out = 13'b0011001110000;
			10:out = 13'b0011101001110;
			11:out = 13'b0100000101101;
			12:out = 13'b0100100001001;
			13:out = 13'b0100111100010;
			14:out = 13'b0101010110100;
			15:out = 13'b0101101111110;
			16:out = 13'b0110000111100;
			17:out = 13'b0110011101101;
			18:out = 13'b0110110001111;
			19:out = 13'b0111000011111;
			20:out = 13'b0111010011100;
			21:out = 13'b0111100000101;
			22:out = 13'b0111101011000;
			23:out = 13'b0111110010100;
			24:out = 13'b0111110111000;
			25:out = 13'b0111111000100;
			26:out = 13'b0111110111000;
			27:out = 13'b0111110010100;
			28:out = 13'b0111101011000;
			29:out = 13'b0111100000101;
			30:out = 13'b0111010011100;
			31:out = 13'b0111000011111;
			32:out = 13'b0110110001111;
			33:out = 13'b0110011101101;
			34:out = 13'b0110000111100;
			35:out = 13'b0101101111110;
			36:out = 13'b0101010110100;
			37:out = 13'b0100111100010;
			38:out = 13'b0100100001001;
			39:out = 13'b0100000101101;
			40:out = 13'b0011101001110;
			41:out = 13'b0011001110000;
			42:out = 13'b0010110010101;
			43:out = 13'b0010010111111;
			44:out = 13'b0001111110000;
			45:out = 13'b0001100101010;
			46:out = 13'b0001001101110;
			47:out = 13'b0000110111110;
			48:out = 13'b0000100011011;
			49:out = 13'b0000010000110;
	default: out = 13'b0000000000000;
	endcase
//			`include "MathFun.vh"
endmodule


//------------------------------------------------
module rcosine_3 #(parameter SAMPLES=50, DW=13, I=0)
(
input	[$clog2(SAMPLES)-1:0] addr, 
output reg signed[I-1:-(DW-I)] out
);
	always@*
	case(addr)
			00:out = -13'b0000000000000;
			01:out = -13'b0000001110111;
			02:out = -13'b0000011011111;
			03:out = -13'b0000100110111;
			04:out = -13'b0000110000000;
			05:out = -13'b0000110111010;
			06:out = -13'b0000111100110;
			07:out = -13'b0001000000100;
			08:out = -13'b0001000010101;
			09:out = -13'b0001000011011;
			10:out = -13'b0001000010110;
			11:out = -13'b0001000001000;
			12:out = -13'b0000111110010;
			13:out = -13'b0000111010101;
			14:out = -13'b0000110110011;
			15:out = -13'b0000110001100;
			16:out = -13'b0000101100010;
			17:out = -13'b0000100110110;
			18:out = -13'b0000100001010;
			19:out = -13'b0000011011101;
			20:out = -13'b0000010110010;
			21:out = -13'b0000010001001;
			22:out = -13'b0000001100001;
			23:out = -13'b0000000111101;
			24:out = -13'b0000000011101;
			25:out = 13'b0000000000000;
			26:out = 13'b0000000011001;
			27:out = 13'b0000000101110;
			28:out = 13'b0000000111111;
			29:out = 13'b0000001001100;
			30:out = 13'b0000001010101;
			31:out = 13'b0000001011011;
			32:out = 13'b0000001011110;
			33:out = 13'b0000001011101;
			34:out = 13'b0000001011011;
			35:out = 13'b0000001010111;
			36:out = 13'b0000001010000;
			37:out = 13'b0000001001001;
			38:out = 13'b0000001000001;
			39:out = 13'b0000000111001;
			40:out = 13'b0000000110000;
			41:out = 13'b0000000101000;
			42:out = 13'b0000000100000;
			43:out = 13'b0000000011000;
			44:out = 13'b0000000010010;
			45:out = 13'b0000000001100;
			46:out = 13'b0000000001000;
			47:out = 13'b0000000000100;
			48:out = 13'b0000000000010;
			49:out = 13'b0000000000000;
		default: out = 13'b0000000000000;
	endcase
//			`include "MathFun.vh"
endmodule
