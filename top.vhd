----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/17/2025 01:12:39 PM
-- Design Name: 
-- Module Name: top - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity top is
    Port( CLK   		: in  STD_LOGIC;
          UART_RXD_OUT 	: out  STD_LOGIC;
          SD_CS         : out STD_LOGIC;
          SD_SCK        : out STD_LOGIC;
          SD_MISO       : in STD_LOGIC;
          SD_MOSI       : out STD_LOGIC;
          dac_MCLK      : OUT STD_LOGIC; -- outputs to PMODI2L DAC
          dac_LRCK      : OUT STD_LOGIC;
          dac_SCLK      : OUT STD_LOGIC;
          dac_SDIN      : OUT std_logic 
    );
end top;

architecture Behavioral of top is

component UART_TX_CTRL
Port(
	SEND : in std_logic;
	DATA : in std_logic_vector(7 downto 0);
	CLK : in std_logic;          
	READY : out std_logic;
	UART_TX : out std_logic
	);
end component;

component dac_if IS
    PORT (
        SCLK : IN STD_LOGIC;
        L_start : IN STD_LOGIC;
        R_start : IN STD_LOGIC;
        L_data : IN signed (15 DOWNTO 0);
        R_data : IN signed (15 DOWNTO 0);
        SDATA : OUT STD_LOGIC
    );
end component;

component sd_controller
Port(
    -- CPU
	clk		: in std_logic;
	n_reset	: in std_logic;
	regAddr	: in std_logic_vector(2 downto 0);
	n_rd	: in std_logic;
	n_wr	: in std_logic;
	dataIn	: in std_logic_vector(7 downto 0);
	dataOut	: out std_logic_vector(7 downto 0);
	-- SD Card SPI connections
	sdCS	: out std_logic;
	sdMOSI	: out std_logic;
	sdMISO	: in std_logic;
	sdSCLK	: out std_logic;
	-- LEDs
	driveLED : out std_logic := '1'
    );
end component;


--The type definition for the UART state machine type. Here is a description of what
--occurs during each state:
-- RST_REG     -- Do Nothing. This state is entered after configuration or a user reset.
--                The state is set to LD_INIT_STR.
-- LD_INIT_STR -- The Welcome String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The welcome string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
-- SEND_CHAR   -- uartSend is set high for a single clock cycle, signaling the character
--                data at sendStr(strIndex) to be registered by the UART_TX_CTRL at the next
--                cycle. Also, strIndex is incremented (behaves as if it were post 
--                incremented after reading the sendStr data). The state is set to RDY_LOW.
-- RDY_LOW     -- Do nothing. Wait for the READY signal from the UART_TX_CTRL to go low, 
--                indicating a send operation has begun. State is set to WAIT_RDY.
-- WAIT_RDY    -- Do nothing. Wait for the READY signal from the UART_TX_CTRL to go high, 
--                indicating a send operation has finished. If READY is high and strEnd = 
--                StrIndex then state is set to WAIT_BTN, else if READY is high and strEnd /=
--                StrIndex then state is set to SEND_CHAR.
-- WAIT_BTN    -- Do nothing. Wait for a button press on BTNU, BTNL, BTND, or BTNR. If a 
--                button press is detected, set the state to LD_BTN_STR.
-- LD_BTN_STR  -- The Button String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The button string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
type UART_STATE_TYPE is (LD_ADDR0_STR, RST_REG, LD_INIT_STR, SEND_CHAR, RDY_LOW, WAIT_RDY, WAIT_SD, LD_DATA_STR, LD_IDLE_STR, LD_CHUNK_STR, LD_STATUS_STR, LD_BUFF_STR);

--The CHAR_ARRAY type is a variable length array of 8 bit std_logic_vectors. 
--Each std_logic_vector contains an ASCII value and represents a character in
--a string. The character at index 0 is meant to represent the first
--character of the string, the character at index 1 is meant to represent the
--second character of the string, and so on.
type CHAR_ARRAY is array (integer range<>) of std_logic_vector(7 downto 0);

constant MAX_STR_LEN : integer := 1200;
constant WELCOME_STR_LEN : natural := 29;
--Welcome string definition. Note that the values stored at each index
--are the ASCII values of the indicated character.
constant WELCOME_STR : CHAR_ARRAY(0 to 28) := (X"0A",  --\n
                                               X"0D",  --\r
                                               X"4E",  --N
                                               X"45",  --E
                                               X"58",  --X
                                               X"59",  --Y
                                               X"53",  --S
                                               X"20",  -- 
                                               X"41",  --A
                                               X"37",  --7
                                               X"20",  -- 
                                               X"47",  --G
                                               X"50",  --P
                                               X"49",  --I
                                               X"4F",  --O
                                               X"2F",  --/
                                               X"55",  --U
                                               X"41",  --A
                                               X"52",  --R
                                               X"54",  --T
                                               X"20",  -- 
                                               X"44",  --D
                                               X"45",  --E
                                               X"4D",  --M
                                               X"4F",  --O
                                               X"21",  --!
                                               X"0A",  --\n
                                               X"0A",  --\n
                                               X"0D"); --\r

constant IDLE_STR : CHAR_ARRAY(0 to 17) := (X"53",
                                            X"44",
                                            X"20",
                                            X"43",
                                            X"41",
                                            X"52",
                                            X"44",
                                            X"20",
                                            X"49",
                                            X"44",
                                            X"4C",
                                            X"45",
                                            X"2E",
                                            X"2E",
                                            X"2E",
                                            X"0A",
                                            X"0A",
                                            X"0D");

constant IDLE_STR_LEN : natural := 18;

signal char : std_logic_vector(7 downto 0);

constant RESET_CNTR_MAX : unsigned(17 downto 0) := "110000110101000000";-- 100,000,000 * 0.002 = 200,000 = clk cycles per 2 ms

--UART_TX_CTRL control signals
signal uartRdy : std_logic;
signal uartSend : std_logic := '0';
signal uartData : std_logic_vector (7 downto 0):= "00000000";
signal uartTX : std_logic;

--Current uart state signal
signal uartState : UART_STATE_TYPE := RST_REG;

--this counter counts the amount of time paused in the UART reset state
signal reset_cntr : unsigned (17 downto 0) := (others=>'0');

--Contains the current string being sent over uart.
signal sendStr : CHAR_ARRAY(0 to (MAX_STR_LEN - 1));

--Contains the length of the current string being sent over uart.
signal strEnd : natural;

--Contains the index of the next character to be sent over uart
--within the sendStr variable.
signal strIndex : natural;


type SD_STATE_TYPE is (INIT, IDLE, READ_STATUS, CHECK_STATUS, WRITE_SDLBA0, WRITE_SDLBA1, WRITE_SDLBA2, SEND_READ, READ_DATA, STORE_DATA, PRE_STATUS_HOLD, READ_DATA_HOLD);

signal SD_state : SD_STATE_TYPE := INIT;
signal SD_next_state : SD_STATE_TYPE;
signal SD_move_status : std_logic_vector(7 downto 0);


-- SD Card signals
signal SD_reset : std_logic := '1';
signal SD_reg : std_logic_vector(2 downto 0);
signal SD_write : std_logic := '1';
signal SD_read : std_logic := '1';
signal SD_dataIn : std_logic_vector(7 downto 0);
signal SD_dataOut : std_logic_vector(7 downto 0);

signal SD_led : std_logic;

type FILE_READ_STATE_TYPE is (INIT, READ_HOLD, WAIT_READ, READ_ENDED, READ_MBR, READ_BPB, PARSE_BPB, READ_FAT, PARSE_FAT, READ_DIR, PARSE_DIR, READ_FILE, PARSE_FILE, IDLE, WAIT_LOAD);
signal file_read_state : FILE_READ_STATE_TYPE := INIT;
signal next_file_read_state : FILE_READ_STATE_TYPE := INIT;


signal read_started : std_logic := '0';
signal read_chunk : std_logic := '0';
signal read_waiting : std_logic := '0';
signal address : std_logic_vector(23 downto 0);
signal buff : CHAR_ARRAY(0 to 511);
signal data : CHAR_ARRAY(0 to 511);
signal reading_file : std_logic := '0';


type PLAYBACK_STATE_TYPE is (IDLE, PARSE_HEADER, READ_SUBCHUNK, PROCESS_SUBCHUNK, READ_SAMPLE);
signal playback_state : PLAYBACK_STATE_TYPE := IDLE;
signal playback_counter : unsigned(31 downto 0) := X"00000000";
constant CLOCK_SPEED : unsigned(31 downto 0) := TO_UNSIGNED(50000000, 32);
signal sample_rate : unsigned(31 downto 0) := TO_UNSIGNED(50000000, 32);
signal channels : unsigned(15 downto 0) := TO_UNSIGNED(1, 16);

signal byte_counter : integer;
signal byte_offset : integer;


signal data_loaded : std_logic := '0';
signal data_read : std_logic := '0';
signal data_ready : std_logic := '0';

signal L_data, R_data : signed(15 downto 0);
SIGNAL dac_load_L, dac_load_R : STD_LOGIC; -- timing pulses to load DAC shift reg.

SIGNAL tcount : unsigned (20 DOWNTO 0) := (OTHERS => '0'); -- timing counter
signal sclk : std_logic;

begin


--playback_counter_max <= TO_UNSIGNED(100000000, 32) / sample_rate - 1;
----------------------------------------------------------
------              UART Control                   -------
----------------------------------------------------------
--Messages are sent on reset and when a button is pressed.

--This counter holds the UART state machine in reset for ~2 milliseconds. This
--will complete transmission of any byte that may have been initiated during 
--FPGA configuration due to the UART_TX line being pulled low, preventing a 
--frame shift error from occuring during the first message.
process(CLK)
begin
  if (rising_edge(CLK)) then
    if (playback_counter >= CLOCK_SPEED * channels) then
        playback_counter <= resize(playback_counter - CLOCK_SPEED * channels, 32);
    else
        playback_counter <= playback_counter + sample_rate;
    end if;
  
    if ((reset_cntr = RESET_CNTR_MAX) or (uartState /= RST_REG)) then
      reset_cntr <= (others=>'0');
    else
      reset_cntr <= reset_cntr + 1;
    end if;
  end if;
end process;

--Next Uart state logic (states described above)
next_uartState_process : process (CLK)
begin
	if (rising_edge(CLK)) then
        case uartState is 
        when RST_REG =>
            if (reset_cntr = RESET_CNTR_MAX) then
              uartState <= LD_INIT_STR;
            end if;
        when LD_INIT_STR =>
            uartState <= SEND_CHAR;
        when SEND_CHAR =>
            uartState <= RDY_LOW;
        when RDY_LOW =>
            uartState <= WAIT_RDY;
        when WAIT_RDY =>
            if (uartRdy = '1') then
                if (strEnd = strIndex) then
                    uartState <= WAIT_SD;
                else
                    uartState <= SEND_CHAR;
                end if;
            end if;
        when WAIT_SD =>
            if (file_read_state = READ_ENDED and reading_file = '0') then
                uartState <= LD_BUFF_STR;
--            elsif (file_read_state = PARSE_DIR and reading_file = '0') then
--                uartState <= LD_BUFF_STR;
            elsif (file_read_state = IDLE) then
                uartState <= LD_IDLE_STR;
            elsif (sd_state = WRITE_SDLBA0 and reading_file = '0') then
                uartState <= LD_ADDR0_STR;
--            elsif (SD_STATE = STORE_DATA) then
--                uartState <= LD_DATA_STR;
--            elsif (file_read_state = WAIT_READ and reading_file = '0') then
--                uartState <= LD_ADDR0_STR;
--            elsif (SD_STATE = CHECK_STATUS) then
--                uartState <= LD_STATUS_STR;
            end if;
        when LD_DATA_STR =>
            uartState <= SEND_CHAR;
        when LD_IDLE_STR =>
            uartState <= SEND_CHAR;
        when LD_CHUNK_STR =>
            uartSTATE <= SEND_CHAR;
        when LD_STATUS_STR =>
            uartSTATE <= SEND_CHAR;
        when LD_BUFF_STR =>
            uartSTATE <= SEND_CHAR;
        when LD_ADDR0_STR =>
            uartSTATE <= SEND_CHAR;
        when others=> --should never be reached
            uartState <= RST_REG;
        end case;
	end if;
end process;

--Loads the sendStr and strEnd signals when a LD state is
--is reached.
string_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
        if (uartState = LD_INIT_STR) then
            sendSTR(0 to 28) <= WELCOME_STR;
            strEND <= WELCOME_STR_LEN;
--	    elsif (uartState = LD_STATUS_STR) then
--            sendSTR(0 to 17) <= (X"53",
--                                 X"54",
--                                 X"41",
--                                 X"54",
--                                 X"55",
--                                 X"53",
--                                 X"3A",
--                                 X"20",
--                                 "0011000" & SD_dataOut(7),
--                                 "0011000" & SD_dataOut(6),
--                                 "0011000" & SD_dataOut(5),
--                                 "0011000" & SD_dataOut(4),
--                                 "0011000" & SD_dataOut(3),
--                                 "0011000" & SD_dataOut(2),
--                                 "0011000" & SD_dataOut(1),
--                                 "0011000" & SD_dataOut(0),
--                                 X"0A",
--                                 X"0D");
--		    strEND <= 18;
--	    elsif (uartState = LD_DATA_STR) then
--            sendSTR(0 to 15) <= (X"44",
--                                 X"41",
--                                 X"54",
--                                 X"41",
--                                 X"3A",
--                                 X"20",
--                                 "0011000" & SD_dataOut(7),
--                                 "0011000" & SD_dataOut(6),
--                                 "0011000" & SD_dataOut(5),
--                                 "0011000" & SD_dataOut(4),
--                                 "0011000" & SD_dataOut(3),
--                                 "0011000" & SD_dataOut(2),
--                                 "0011000" & SD_dataOut(1),
--                                 "0011000" & SD_dataOut(0),
--                                 X"0A",
--                                 X"0D");
--		    strEND <= 16;
		elsif (uartState = LD_ADDR0_STR) then
            sendSTR(0 to 31) <= (X"41",
                                 X"44",
                                 X"44",
                                 X"52",
                                 X"3A",
                                 X"20",
                                 "0011000" & address(23),
                                 "0011000" & address(22),
                                 "0011000" & address(21),
                                 "0011000" & address(20),
                                 "0011000" & address(19),
                                 "0011000" & address(18),
                                 "0011000" & address(17),
                                 "0011000" & address(16),
                                 "0011000" & address(15),
                                 "0011000" & address(14),
                                 "0011000" & address(13),
                                 "0011000" & address(12),
                                 "0011000" & address(11),
                                 "0011000" & address(10),
                                 "0011000" & address(9),
                                 "0011000" & address(8),
                                 "0011000" & address(7),
                                 "0011000" & address(6),
                                 "0011000" & address(5),
                                 "0011000" & address(4),
                                 "0011000" & address(3),
                                 "0011000" & address(2),
                                 "0011000" & address(1),
                                 "0011000" & address(0),
                                 X"0A",
                                 X"0D");
		    strEND <= 32;
		elsif (uartState = LD_IDLE_STR) then
		    sendSTR(0 to 17) <= IDLE_STR;
		    strEND <= IDLE_STR_LEN;
		elsif (uartState = LD_BUFF_STR) then
            for i in 0 to 511 loop
                case buff(i)(7 downto 4) is
                when X"0" =>
                    sendSTR(2*i) <= X"30";
                when X"1" =>
                    sendSTR(2*i) <= X"31";
                when X"2" =>
                    sendSTR(2*i) <= X"32";
                when X"3" =>
                    sendSTR(2*i) <= X"33";
                when X"4" =>
                    sendSTR(2*i) <= X"34";
                when X"5" =>
                    sendSTR(2*i) <= X"35";
                when X"6" =>
                    sendSTR(2*i) <= X"36";
                when X"7" =>
                    sendSTR(2*i) <= X"37";
                when X"8" =>
                    sendSTR(2*i) <= X"38";
                when X"9" =>
                    sendSTR(2*i) <= X"39";
                when X"A" =>
                    sendSTR(2*i) <= X"41";
                when X"B" =>
                    sendSTR(2*i) <= X"42";
                when X"C" =>
                    sendSTR(2*i) <= X"43";
                when X"D" =>
                    sendSTR(2*i) <= X"44";
                when X"E" =>
                    sendSTR(2*i) <= X"45";
                when X"F" =>
                    sendSTR(2*i) <= X"46";
                when others =>
                    sendSTR(2*i) <= X"30";
                end case;
                case buff(i)(3 downto 0) is
                when X"0" =>
                    sendSTR(2*i+1) <= X"30";
                when X"1" =>
                    sendSTR(2*i+1) <= X"31";
                when X"2" =>
                    sendSTR(2*i+1) <= X"32";
                when X"3" =>
                    sendSTR(2*i+1) <= X"33";
                when X"4" =>
                    sendSTR(2*i+1) <= X"34";
                when X"5" =>
                    sendSTR(2*i+1) <= X"35";
                when X"6" =>
                    sendSTR(2*i+1) <= X"36";
                when X"7" =>
                    sendSTR(2*i+1) <= X"37";
                when X"8" =>
                    sendSTR(2*i+1) <= X"38";
                when X"9" =>
                    sendSTR(2*i+1) <= X"39";
                when X"A" =>
                    sendSTR(2*i+1) <= X"41";
                when X"B" =>
                    sendSTR(2*i+1) <= X"42";
                when X"C" =>
                    sendSTR(2*i+1) <= X"43";
                when X"D" =>
                    sendSTR(2*i+1) <= X"44";
                when X"E" =>
                    sendSTR(2*i+1) <= X"45";
                when X"F" =>
                    sendSTR(2*i+1) <= X"46";
                when others =>
                    sendSTR(2*i+1) <= X"30";
                end case;
            end loop;
            sendSTR(1024 to 1025) <= X"0A" & X"0D";
            strEND <= 1026;
		end if;
	end if;
end process;

--Conrols the strIndex signal so that it contains the index
--of the next character that needs to be sent over uart
char_count_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR or uartState = WAIT_SD) then
			strIndex <= 0;
		elsif (uartState = SEND_CHAR) then
			strIndex <= strIndex + 1;
		end if;
	end if;
end process;

--Controls the UART_TX_CTRL signals
char_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = SEND_CHAR) then
			uartSend <= '1';
			uartData <= sendStr(strIndex);
		else
			uartSend <= '0';
		end if;
	end if;
end process;

--Component used to send a byte of data over a UART line.
Inst_UART_TX_CTRL: UART_TX_CTRL port map(
		SEND => uartSend,
		DATA => uartData,
		CLK => CLK,
		READY => uartRdy,
		UART_TX => UART_RXD_OUT 
	);

Inst_SD_CTRL: sd_controller port map(
        -- CPU
        clk	=> CLK,
        n_reset => SD_reset,
        regAddr => SD_reg,
        n_rd => SD_read,
        n_wr => SD_write,
        dataIn => SD_dataIn,
        dataOut => SD_dataOut,
        -- SD Card SPI connections
        sdCS => SD_CS,
        sdMOSI => SD_MOSI,
        sdMISO => SD_MISO,
        sdSCLK => SD_SCK,
        -- LEDs
        driveLED => SD_led
);

next_SDState_process: process (CLK)
    --variable byte_counter : integer := 0;
begin
	if (rising_edge(CLK) and uartState = WAIT_SD) then
        SD_read <= '1';     -- These signals are active low, 
        SD_write <= '1';    -- so set them to high by default.
        SD_reset <= '1';    -- Set to low during state transitions to read or write
        read_started <= '0';
        case SD_state is 
        when INIT =>
            SD_reset <= '0';
            byte_counter <= 0;
            SD_next_state <= IDLE;
            SD_move_status <= X"80";
            SD_state <= PRE_STATUS_HOLD;
            
        when IDLE =>
            if (read_waiting = '1') then
                SD_next_state <= WRITE_SDLBA0;
                SD_move_status <= X"80";
                SD_state <= READ_STATUS;
            end if;
        
        when PRE_STATUS_HOLD =>
            SD_state <= READ_STATUS;
        
        when READ_STATUS =>
            SD_reg <= "001";
            SD_state <= CHECK_STATUS;
            
        when CHECK_STATUS =>
            if (SD_dataOut = SD_move_status) then
                SD_state <= SD_next_state;
            end if;
        
        when WRITE_SDLBA0 =>
            SD_reg <= "010";
            SD_dataIn <= address(7 downto 0);
            SD_write <= '0';
            SD_next_state <= WRITE_SDLBA1;
            SD_move_status <= X"80";
            SD_state <= PRE_STATUS_HOLD;
        
        when WRITE_SDLBA1 =>
            SD_reg <= "011";
            SD_dataIn <= address(15 downto 8);
            SD_write <= '0';
            SD_next_state <= WRITE_SDLBA2;
            SD_move_status <= X"80";
            SD_state <= PRE_STATUS_HOLD;
        
        when WRITE_SDLBA2 =>
            SD_reg <= "100";
            SD_dataIn <= address(23 downto 16);
            SD_write <= '0';
            SD_next_state <= SEND_READ;
            SD_move_status <= X"80";
            SD_state <= PRE_STATUS_HOLD;
            
        when SEND_READ =>
            read_started <= '1';
            SD_reg <= "001";
            SD_dataIn <= X"00";
            SD_write <= '0';
            SD_next_state <= READ_DATA;
            SD_move_status <= X"E0";
            SD_state <= PRE_STATUS_HOLD;
        
        when READ_DATA =>
            SD_reg <= "000";
            SD_read <= '0';
            SD_state <= READ_DATA_HOLD;
            
        when READ_DATA_HOLD =>
            SD_state <= STORE_DATA;
        
        when STORE_DATA =>
            buff(byte_counter) <= SD_dataOut;
            if (byte_counter = 511) then
                byte_counter <= 0;
                SD_next_state <= IDLE;
                SD_move_status <= X"80";
                SD_state <= PRE_STATUS_HOLD;
            else 
                byte_counter <= byte_counter + 1;
                SD_next_state <= READ_DATA;
                SD_move_status <= X"E0";
                SD_state <= PRE_STATUS_HOLD;
            end if;
        when others =>
            SD_state <= INIT;
        end case;
    end if;
end process;

read_chunk_flag : process (CLK, read_chunk, read_started)
begin
    if (read_started = '1') then
        read_waiting <= '0';
    elsif (rising_edge(read_chunk)) then
        read_waiting <= '1';
    end if;
end process;

file_reader : process (CLK)
    variable reserved_sectors : unsigned(15 downto 0);
    variable sectors_per_fat : unsigned(31 downto 0);
    variable fat_copies : unsigned(7 downto 0);
    variable current_sector : unsigned(23 downto 0);
    variable sectors_per_cluster : unsigned(7 downto 0);
    variable starting_cluster : unsigned(31 downto 0);
    variable fat_start_sector : unsigned(23 downto 0);
    variable data_start_sector : unsigned(23 downto 0);
    
    variable dir_cluster : unsigned(23 downto 0);
    variable dir_sector : unsigned(7 downto 0);
    variable entry_number : integer := 0;
    variable file_entry : CHAR_ARRAY(0 to 31);
    
    variable file_cluster : unsigned(23 downto 0);
    variable file_sector : unsigned(7 downto 0);
    variable file_size : unsigned(31 downto 0);
    
    variable current_cluster : unsigned(23 downto 0);
    variable fat_offset : integer;
    variable fat_entry : unsigned(23 downto 0);

begin
    if (rising_edge(CLK) and uartState = WAIT_SD) then
        read_chunk <= '0';
        data_loaded <= '0';
        case file_read_state is
            when INIT =>
                if (SD_state = IDLE) then
                    entry_number := 0;
                    file_read_state <= READ_MBR;
                end if;
            when READ_HOLD =>
                read_chunk <= '1';
                file_read_state <= WAIT_READ;
            when WAIT_READ =>
                if (SD_state = IDLE and read_waiting = '0') then
                    file_read_state <= READ_ENDED;
                end if;
            when READ_ENDED =>
                file_read_state <= next_file_read_state;
            when IDLE =>
                file_read_state <= IDLE;
            when READ_MBR =>    -- Master Boot Record
                address <= X"000000";
                next_file_read_state <= READ_BPB;
                file_read_state <= READ_HOLD;
            when READ_BPB =>    -- BIOS Parameter Block
                current_sector := unsigned(std_logic_vector'(buff(456) & buff(455) & buff(454)));
                address <= std_logic_vector(current_sector);
                next_file_read_state <= PARSE_BPB;
                file_read_state <= READ_HOLD;
            when PARSE_BPB =>
                sectors_per_cluster := unsigned(buff(13));
                reserved_sectors := unsigned(std_logic_vector'(buff(15) & buff(14)));
                fat_copies := unsigned(buff(16));
                sectors_per_fat := unsigned(std_logic_vector'(buff(39) & buff(38) & buff(37) & buff(36)));
                starting_cluster := unsigned(std_logic_vector'(buff(47) & buff(46) & buff(45) & buff(44)));
                fat_start_sector := current_sector + reserved_sectors;
                data_start_sector := resize((fat_start_sector + fat_copies * sectors_per_fat), 24);
                dir_cluster := resize(starting_cluster, 24);
                dir_sector := X"00";
                file_read_state <= READ_DIR;
            when READ_DIR =>
                if (dir_sector = sectors_per_cluster) then
                    dir_sector := X"00";
                    current_cluster := dir_cluster;
                    file_read_state <= READ_FAT;
                else
                    address <= std_logic_vector(resize((data_start_sector + sectors_per_cluster * (dir_cluster - starting_cluster) + dir_sector), 24));
                    next_file_read_state <= PARSE_DIR;
                    dir_sector := dir_sector + 1;
                    file_read_state <= READ_HOLD;
                end if;
            when PARSE_DIR =>
                if (entry_number = 16) then -- If we have read all the entries in the sector, move to the next sector
                    entry_number := 0;
                    file_read_state <= READ_DIR;
                else
                    for i in 0 to 31 loop -- Read the entry
                        file_entry(i) := buff(entry_number*32 + i);
                    end loop;
                    entry_number := entry_number + 1;
                    if (file_entry(8 to 10) = (X"57", X"41", X"56") and file_entry(26 to 27) /= (X"00", X"00")) then -- If .WAV file and starting cluster is not 0
                        file_cluster := unsigned(std_logic_vector'(file_entry(20) & file_entry(27) & file_entry(26)));
                        file_sector := X"00";
                        file_size := unsigned(std_logic_vector'(file_entry(31) & file_entry(30) & file_entry(29) & file_entry(28)));
                        reading_file <= '1';
                        file_read_state <= READ_FILE;
                    else
                        file_read_state <= PARSE_DIR;
                    end if;
                end if;
            when READ_FILE =>
                if (file_sector = sectors_per_cluster) then
                    file_sector := X"00";
                    current_cluster := file_cluster;
                    file_read_state <= READ_FAT;
                else
                    address <= std_logic_vector(resize((data_start_sector + sectors_per_cluster * (file_cluster - starting_cluster) + file_sector), 24));
                    file_sector := file_sector + 1;
                    next_file_read_state <= PARSE_FILE;
                    file_read_state <= READ_HOLD;
                end if;
            when PARSE_FILE =>
                data_loaded <= '1';
                file_read_state <= WAIT_LOAD;
            when WAIT_LOAD =>
                if (data_ready = '0') then
                    file_read_state <= READ_FILE;
                end if;
                    
            when READ_FAT =>
                address <= std_logic_vector(resize((fat_start_sector + (current_cluster / 128)), 24));
                next_file_read_state <= PARSE_FAT;
                file_read_state <= READ_HOLD;
            when PARSE_FAT =>
                fat_offset := TO_INTEGER(resize(((current_cluster * 4) mod 512), 9));
                fat_entry := unsigned(std_logic_vector'(buff(fat_offset+2) & buff(fat_offset+1) & buff(fat_offset)));
                if (reading_file = '0' and fat_entry = X"FFFFFF") then
                    file_read_state <= INIT;
                elsif (reading_file = '0') then
                    dir_cluster := fat_entry;
                    file_read_state <= READ_DIR;
                elsif (reading_file = '1' and fat_entry = X"FFFFFF") then
                    reading_file <= '0';
                    dir_sector := dir_sector - 1;
                    file_read_state <= READ_DIR;
                elsif (reading_file = '1') then
                    file_cluster := fat_entry;
                    file_read_state <= READ_FILE;
                end if;
            when others =>
                file_read_state <= INIT;
        end case;
    end if;
end process;

data_ready_flag : process (CLK, data_loaded, data_read) is
begin
    if (data_read = '1') then
        data_ready <= '0';
    elsif (rising_edge(data_loaded)) then
        data_ready <= '1';
    end if;
end process;


playback : process(CLK, playback_counter)
    variable block_align : integer;
    variable bits_per_sample : unsigned(15 downto 0);
    variable chunk_id : std_logic_vector(31 downto 0);
    variable chunk_size : unsigned(31 downto 0);
begin
    if (rising_edge(CLK) and playback_counter >= CLOCK_SPEED*channels and uartState = WAIT_SD) then
        data_read <= '0';
        case playback_state is
        when IDLE =>
            if (data_ready = '1' and reading_file = '1') then
                data <= buff;
                byte_offset <= 0;
                data_read <= '1';
                playback_state <= PARSE_HEADER;
            end if;
        when PARSE_HEADER =>
            channels <= unsigned(std_logic_vector'(data(23) & data(22)));
            sample_rate <= unsigned(std_logic_vector'(data(27) & data(26) & data(25) & data(24)));
            block_align := TO_INTEGER(unsigned(std_logic_vector'(data(33) & data(32))));
            bits_per_sample := unsigned(std_logic_vector'(data(35) & data(34)));
            byte_offset <= 36;
            playback_state <= READ_SUBCHUNK;
        when READ_SUBCHUNK =>
            chunk_id := std_logic_vector'(data(byte_offset) & data(byte_offset+1) & data(byte_offset+2) & data(byte_offset+3));
            chunk_size := unsigned(std_logic_vector'(data(byte_offset+7) & data(byte_offset+6) & data(byte_offset+5) & data(byte_offset+4)));
            playback_state <= PROCESS_SUBCHUNK;
            
        when PROCESS_SUBCHUNK =>
            if (chunk_id = X"4c495354") then
                byte_offset <= byte_offset + 8;
                playback_state <= READ_SAMPLE;
            else
                byte_offset <= byte_offset + TO_INTEGER(chunk_size) + 8;
                playback_state <= READ_SUBCHUNK;
            end if;
        when READ_SAMPLE =>
            if (reading_file = '0') then
                playback_state <= IDLE;
            else
                if (bits_per_sample = 16) then
                    L_data <= signed(std_logic_vector'(data(byte_offset+1) & data(byte_offset)));
                    if (channels = 1) then
                        R_data <= L_data;
                    elsif (channels = 2) then
                        R_data <= signed(std_logic_vector'(data(byte_offset+3) & data(byte_offset+2)));
                    end if;
                elsif (bits_per_sample = 8) then
                    L_data <= signed(std_logic_vector'(data(byte_offset) & X"00"));
                    if (channels = 1) then
                        R_data <= L_data;
                    elsif (channels = 2) then
                        R_data <= signed(std_logic_vector'(data(byte_offset+1) & X"00"));
                    end if;
                end if;
                if (byte_offset = 512 - block_align) then
                    data <= buff;
                    byte_offset <= 0;
                    data_read <= '1';
                else
                    byte_offset <= byte_offset + block_align;
                end if;
                playback_state <= READ_SAMPLE;
            end if;
        when others =>
            playback_state <= IDLE;
        end case;
    end if;
end process;


dac : dac_if PORT MAP(
    SCLK => sclk, -- instantiate parallel to serial DAC interface
    L_start => dac_load_L, 
    R_start => dac_load_R, 
    L_data => L_data, 
    R_data => R_data, 
    SDATA => dac_SDIN 
);

tim_pr : PROCESS (CLK)
BEGIN
    if rising_edge(CLK) then
        IF (tcount(9 DOWNTO 0) >= X"00F") AND (tcount(9 DOWNTO 0) < X"02E") THEN
            dac_load_L <= '1';
        ELSE
            dac_load_L <= '0';
        END IF;
        IF (tcount(9 DOWNTO 0) >= X"20F") AND (tcount(9 DOWNTO 0) < X"22E") THEN
            dac_load_R <= '1';
        ELSE 
            dac_load_R <= '0';
        END IF;
        tcount <= tcount + 1;
    end if;
END PROCESS;

dac_MCLK <= NOT tcount(1); -- DAC master clock (12.5 MHz)
dac_LRCK <= tcount(9); -- audio sampling rate (48.8 kHz)
sclk <= tcount(4); -- serial data clock (1.56 MHz)
dac_SCLK <= sclk; -- also sent to DAC as SCLK

end Behavioral;
