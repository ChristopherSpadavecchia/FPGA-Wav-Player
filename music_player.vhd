library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.Common.ALL;

entity music_player is
    Port( CLK   		: IN  STD_LOGIC; -- 50 MHz Clock
    
          SD_CS         : OUT STD_LOGIC; -- SD Card
          SD_SCK        : OUT STD_LOGIC;
          SD_MISO       : IN STD_LOGIC;
          SD_MOSI       : OUT STD_LOGIC;
          
          dac_MCLK      : OUT STD_LOGIC; -- outputs to PMODI2L DAC
          dac_LRCK      : OUT STD_LOGIC;
          dac_SCLK      : OUT STD_LOGIC;
          dac_SDIN      : OUT std_logic
    );
end music_player;

architecture Behavioral of music_player is

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

component sd_reader
    Port(
        CLK   		    : IN  STD_LOGIC;
        SD_CS           : OUT STD_LOGIC;
        SD_SCK          : OUT STD_LOGIC;
        SD_MISO         : IN STD_LOGIC;
        SD_MOSI         : OUT STD_LOGIC;
        address         : IN STD_LOGIC_VECTOR(23 downto 0);
        buff            : OUT CHAR_ARRAY(0 to 511);
        read            : IN STD_LOGIC;
        sd_idle         : OUT BOOLEAN;
        reset           : IN STD_LOGIC
    );
end component;

component wav_playback
    Port( 
        CLK   		    : IN  STD_LOGIC; -- 50 MHz Clock
        reset           : IN  STD_LOGIC;
        data_loaded     : IN  STD_LOGIC;
        reading_file    : IN  STD_LOGIC;
        data_ready_o    : OUT STD_LOGIC;
        buff            : IN CHAR_ARRAY(0 to 511);
        L_data          : OUT signed (15 DOWNTO 0);
        R_data          : OUT signed (15 DOWNTO 0)
    );
end component;

type FILE_READ_STATE_TYPE is (INIT, READ_HOLD, WAIT_READ, READ_ENDED, READ_MBR, PARSE_MBR, READ_BPB, PARSE_BPB, READ_FAT, PARSE_FAT, READ_DIR, PARSE_DIR, READ_FILE, FILE_READY, IDLE, WAIT_LOAD);
signal file_read_state : FILE_READ_STATE_TYPE;
signal next_file_read_state : FILE_READ_STATE_TYPE;

signal address : std_logic_vector(23 downto 0) := X"000000";
signal buff : CHAR_ARRAY(0 to 511);
signal enable : std_logic := '0';

signal read_chunk : std_logic := '0';
signal sd_idle : BOOLEAN;
signal sd_reset : STD_LOGIC := '1';

signal reading_file : std_logic := '0';
signal data_loaded : std_logic := '0';
signal data_ready : std_logic := '0';
signal playback_reset : STD_LOGIC := '1';
signal L_data, R_data : signed(15 downto 0) := X"0000";

SIGNAL dac_load_L, dac_load_R : STD_LOGIC := '0'; -- timing pulses to load DAC shift reg.
SIGNAL tcount : unsigned (20 DOWNTO 0) := (OTHERS => '0'); -- timing counter
signal sclk : std_logic := '0';

begin

process (CLK)
    variable counter : integer := 0;
    variable start_delay : integer := 10000000;
begin
    if (rising_edge(CLK) and enable = '0') then
        if counter < start_delay then
            counter := counter + 1;
        else
            enable <= '1';
        end if;
    end if;
end process;


file_reader : process (CLK)
    -- Info from the BPB
    variable reserved_sectors : unsigned(15 downto 0) := X"0000";
    variable sectors_per_fat : unsigned(31 downto 0) := X"00000000";
    variable fat_copies : unsigned(7 downto 0) := X"00";
    variable current_sector : unsigned(23 downto 0) := X"000000";
    variable sectors_per_cluster : unsigned(7 downto 0) := X"00";
    variable starting_cluster : unsigned(31 downto 0) := X"00000000";
    variable fat_start_sector : unsigned(23 downto 0) := X"000000";
    variable data_start_sector : unsigned(23 downto 0) := X"000000";
    
    -- Variables for traversing the file system
    variable dir_cluster : unsigned(23 downto 0) := X"000000";
    variable dir_sector : unsigned(7 downto 0) := X"00";
    variable entry_number : integer := 0;
    variable file_entry : CHAR_ARRAY(0 to 31);
    
    -- Variables for reading through a file
    variable file_cluster : unsigned(23 downto 0) := X"000000";
    variable file_sector : unsigned(7 downto 0) := X"00";
    variable file_size : unsigned(31 downto 0) := X"00000000";
    
    -- Variables for reading the fat
    variable current_cluster : unsigned(23 downto 0) := X"000000";
    variable fat_offset : integer := 0;
    variable fat_entry : unsigned(23 downto 0) := X"000000";

begin
    if (enable = '0') then
        file_read_state <= INIT;
    elsif (rising_edge(CLK)) then
        read_chunk <= '0';
        data_loaded <= '0';
        sd_reset <= '0';
        playback_reset <= '0';
        case file_read_state is
            when INIT =>
                sd_reset <= '1';
                playback_reset <= '1';
                reading_file <= '0';
                entry_number := 0;
                file_read_state <= READ_MBR;
                
            when READ_HOLD =>
                read_chunk <= '1';
                file_read_state <= WAIT_READ;
                
            when WAIT_READ =>
                if (sd_idle) then
                    file_read_state <= next_file_read_state;
                end if;
                
            when IDLE =>
                
            when READ_MBR =>    -- Master Boot Record
                address <= X"000000";
                next_file_read_state <= PARSE_MBR;
                file_read_state <= READ_HOLD;
                
            when PARSE_MBR =>
                current_sector := unsigned(std_logic_vector'(buff(456) & buff(455) & buff(454)));
                file_read_state <= READ_BPB;
                
            when READ_BPB =>    -- BIOS Parameter Block
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
                    dir_sector := dir_sector + 1;
                    next_file_read_state <= PARSE_DIR;
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
                    next_file_read_state <= FILE_READY;
                    file_read_state <= READ_HOLD;
                end if;
                
            when FILE_READY =>
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

sd_ctrl : sd_reader PORT MAP(
    CLK => CLK,
    SD_CS => SD_CS,
    SD_SCK => SD_SCK,
    SD_MISO => SD_MISO,
    SD_MOSI => SD_MOSI,
    address => address,
    buff => buff,
    read => read_chunk,
    sd_idle => sd_idle,
    reset => sd_reset
);

wav_player : wav_playback PORT MAP(
    CLK => CLK,
    reset => playback_reset,
    data_loaded => data_loaded,
    reading_file => reading_file,
    data_ready_o => data_ready,
    buff => buff,
    L_data => L_data,
    R_data => R_data
);

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
