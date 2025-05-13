library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.Common.ALL;

entity sd_reader is
    Port( CLK   		: IN  STD_LOGIC;
          SD_CS         : OUT STD_LOGIC;
          SD_SCK        : OUT STD_LOGIC;
          SD_MISO       : IN STD_LOGIC;
          SD_MOSI       : OUT STD_LOGIC;
          address       : IN STD_LOGIC_VECTOR(23 downto 0);
          buff          : OUT CHAR_ARRAY(0 to 511);
          read          : IN STD_LOGIC;
          sd_idle       : OUT BOOLEAN;
          reset         : IN STD_LOGIC
    );
end sd_reader;

architecture Behavioral of sd_reader is
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
	driveLED : out std_logic
    );
end component;

-- SD Card signals
signal SD_reset : std_logic := '0';
signal SD_reg : std_logic_vector(2 downto 0) := "000";
signal SD_write : std_logic := '1';
signal SD_read : std_logic := '1';
signal SD_dataIn : std_logic_vector(7 downto 0) := X"00";
signal SD_dataOut : std_logic_vector(7 downto 0);

signal SD_led : std_logic;


type SD_STATE_TYPE is (DELAY, INIT, IDLE, READ_STATUS, CHECK_STATUS, WRITE_SDLBA0, WRITE_SDLBA1, WRITE_SDLBA2, SEND_READ, READ_DATA, STORE_DATA, PRE_STATUS_HOLD);

signal SD_state : SD_STATE_TYPE := INIT;
signal SD_next_state : SD_STATE_TYPE := INIT;
signal SD_move_status : std_logic_vector(7 downto 0) := X"00";

signal read_started : std_logic := '0';
signal read_waiting : std_logic := '0';

begin

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


read_chunk_flag : process (read, read_started)
begin
    if (read_started = '1') then
        read_waiting <= '0';
    elsif (rising_edge(read)) then
        read_waiting <= '1';
    end if;
end process;

sd_idle <= read_waiting = '0' and SD_state = IDLE;

next_SDState_process: process (CLK)
    variable byte_counter : integer := 0;
    constant delay_amount : integer := 100000;
    variable delay_count : integer;
begin

	if (rising_edge(CLK)) then
	    SD_read <= '1';     -- These signals are active low, 
        SD_write <= '1';    -- so set them to high by default.
        SD_reset <= '1';    -- Set to low during state transitions to read or write
        read_started <= '0';
	    if (reset = '1') then
            SD_state <= INIT;
            byte_counter := 0;
        else
            case SD_state is 
            when INIT =>
                SD_reset <= '0';
                byte_counter := 0;
                delay_count := delay_amount;
                SD_next_state <= IDLE;
                SD_move_status <= X"80";
                SD_state <= READ_STATUS;
                
            when IDLE =>
                if (read_waiting = '1') then
                    SD_next_state <= DELAY;
                    SD_move_status <= X"80";
                    SD_state <= READ_STATUS;
                end if;
                
            when PRE_STATUS_HOLD =>
                SD_state <= READ_STATUS;
            
            when READ_STATUS =>
                SD_reg <= "001";
                SD_state <= CHECK_STATUS;
            
            when DELAY =>
                if (delay_count > 0) then
                    delay_count := delay_count - 1;
                else
                    SD_state <= WRITE_SDLBA0;
                end if;
                
            when CHECK_STATUS =>
                if (SD_dataOut = SD_move_status) then
                    SD_state <= SD_next_state;
                elsif (SD_dataOut = X"A0") then
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
                SD_state <= STORE_DATA;
            
            when STORE_DATA =>
                buff(byte_counter) <= SD_dataOut;
                if (byte_counter = 511) then
                    byte_counter := 0;
                    SD_next_state <= IDLE;
                    SD_move_status <= X"80";
                    SD_state <= READ_STATUS;
                else 
                    byte_counter := byte_counter + 1;
                    SD_next_state <= READ_DATA;
                    SD_move_status <= X"E0";
                    SD_state <= READ_STATUS;
                end if;
                
            when others =>
                SD_state <= INIT;
            end case;
        end if;
    end if;
end process;

end Behavioral;
