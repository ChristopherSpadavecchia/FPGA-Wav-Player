library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.Common.ALL;

entity wav_playback is
    Port( CLK   		: IN  STD_LOGIC; -- 50 MHz Clock
          reset         : IN  STD_LOGIC;
          data_loaded   : IN  STD_LOGIC;
          reading_file  : IN  STD_LOGIC;
          data_ready_o  : OUT STD_LOGIC;
          buff          : IN CHAR_ARRAY(0 to 511);
          L_data        : OUT signed (15 DOWNTO 0);
          R_data        : OUT signed (15 DOWNTO 0)
    );
end wav_playback;

architecture Behavioral of wav_playback is

type PLAYBACK_STATE_TYPE is (IDLE, PARSE_FMT, READ_SUBCHUNK, PROCESS_SUBCHUNK, READ_SAMPLE);
signal playback_state : PLAYBACK_STATE_TYPE := IDLE;
constant CLOCK_SPEED : unsigned(31 downto 0) := TO_UNSIGNED(50000000, 32);
signal data_read : std_logic := '0';
signal data_ready : std_logic := '0';

begin
data_ready_o <= data_ready;

data_ready_flag : process (data_loaded, data_read) is
begin
    if (data_read = '1') then
        data_ready <= '0';
    elsif (rising_edge(data_loaded)) then
        data_ready <= '1';
    end if;
end process;

playback : process(CLK)
    variable byte_offset : integer := 0;
    variable block_align : integer := 4;
    variable bits_per_sample : unsigned(15 downto 0) := X"0100";
    variable chunk_id : std_logic_vector(31 downto 0) := X"00000000";
    variable chunk_size : unsigned(31 downto 0) := X"00000000";
    variable data : CHAR_ARRAY(0 to 511);
    variable playback_counter : unsigned(31 downto 0) := X"00000000";
    variable sample_rate : unsigned(31 downto 0) := X"00000001";
    variable channels : unsigned(15 downto 0) := X"0000";

begin
    if (rising_edge(CLK)) then
        if (playback_counter >= CLOCK_SPEED * channels) then
            playback_counter := resize(playback_counter - CLOCK_SPEED * channels, 32);
        else
            playback_counter := playback_counter + sample_rate;
        end if;
    
        data_read <= '0';
        if (reset = '1') then
            sample_rate := TO_UNSIGNED(1, 32);
            channels := TO_UNSIGNED(1, 16);
            playback_state <= IDLE;
        elsif (playback_counter >= CLOCK_SPEED*channels) then
            case playback_state is
            when IDLE =>
                if (data_ready = '1' and reading_file = '1') then
                    data := buff;
                    byte_offset := 0;
                    data_read <= '1';
                    playback_state <= PARSE_FMT;
                end if;
            when PARSE_FMT =>
                channels := unsigned(std_logic_vector'(data(23) & data(22)));
                sample_rate := unsigned(std_logic_vector'(data(27) & data(26) & data(25) & data(24)));
                block_align := TO_INTEGER(unsigned(std_logic_vector'(data(33) & data(32))));
                bits_per_sample := unsigned(std_logic_vector'(data(35) & data(34)));
                byte_offset := 36;
                playback_state <= READ_SUBCHUNK;
            when READ_SUBCHUNK =>
                chunk_id := std_logic_vector'(data(byte_offset) & data(byte_offset+1) & data(byte_offset+2) & data(byte_offset+3));
                chunk_size := unsigned(std_logic_vector'(data(byte_offset+7) & data(byte_offset+6) & data(byte_offset+5) & data(byte_offset+4)));
                playback_state <= PROCESS_SUBCHUNK;
                
            when PROCESS_SUBCHUNK =>
                if (chunk_id = X"4c495354") then
                    byte_offset := byte_offset + 8;
                    playback_state <= READ_SAMPLE;
                else
                    byte_offset := byte_offset + TO_INTEGER(chunk_size) + 8;
                    playback_state <= READ_SUBCHUNK;
                end if;
            when READ_SAMPLE =>
                if (reading_file = '0') then
                    sample_rate := TO_UNSIGNED(1, 32);
                    channels := TO_UNSIGNED(1, 16);
                    playback_state <= IDLE;
                else
                    if (bits_per_sample = 16) then
                        L_data <= signed(std_logic_vector'(data(byte_offset+1) & data(byte_offset)));
                        if (channels = 1) then
                            R_data <= signed(std_logic_vector'(data(byte_offset+1) & data(byte_offset)));
                        elsif (channels = 2) then
                            R_data <= signed(std_logic_vector'(data(byte_offset+3) & data(byte_offset+2)));
                        end if;
                    elsif (bits_per_sample = 8) then
                        L_data <= signed(std_logic_vector'(data(byte_offset) & X"00"));
                        if (channels = 1) then
                            R_data <= signed(std_logic_vector'(data(byte_offset) & X"00"));
                        elsif (channels = 2) then
                            R_data <= signed(std_logic_vector'(data(byte_offset+1) & X"00"));
                        end if;
                    end if;
                    if (byte_offset = 512 - block_align) then
                        data := buff;
                        byte_offset := 0;
                        data_read <= '1';
                    else
                        byte_offset := byte_offset + block_align;
                    end if;
                    playback_state <= READ_SAMPLE;
                end if;
            when others =>
                playback_state <= IDLE;
            end case;
        end if;
    end if;
end process;

end Behavioral;
