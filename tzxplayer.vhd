---------------------------------------------------------------------------------
-- TZX player
-- by György Szombathelyi
-- basic idea for the structure based on c1530 tap player by darfpga
--
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_ARITH.ALL;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity tzxplayer is
generic (
	TZX_MS : integer := 64000       -- CE periods for one milliseconds
);
port(
	clk             : in std_logic;
	ce              : in std_logic;
	restart_tape    : in std_logic; -- keep to 1 to long enough to clear fifo
	                                -- reset tap header bytes skip counter

	host_tap_in     : in std_logic_vector(7 downto 0);  -- 8bits fifo input
	host_tap_wrreq  : in std_logic;                     -- set to 1 for 1 clk to write 1 word
	tap_fifo_wrfull : out std_logic;                    -- do not write when fifo tap_fifo_full = 1
	tap_fifo_error  : out std_logic;                    -- fifo fall empty (unrecoverable error)

	cass_read  : buffer std_logic;   -- tape read signal
	cass_motor : in  std_logic    -- 1 = tape motor is powered
);
end tzxplayer;

architecture struct of tzxplayer is

-- ZX Spectrum
constant NORMAL_PILOT_LEN    : integer := 2168;
constant NORMAL_SYNC1_LEN    : integer := 667;
constant NORMAL_SYNC2_LEN    : integer := 735;
constant NORMAL_ZERO_LEN     : integer := 855;
constant NORMAL_ONE_LEN      : integer := 1710;
constant NORMAL_PILOT_PULSES : integer := 4031;

-- Amstrad CPC
--constant NORMAL_PILOT_LEN    : integer := 2000;
--constant NORMAL_SYNC1_LEN    : integer := 855;
--constant NORMAL_SYNC2_LEN    : integer := 855;
--constant NORMAL_ZERO_LEN     : integer := 855;
--constant NORMAL_ONE_LEN      : integer := 1710;
--constant NORMAL_PILOT_PULSES : integer := 4096;

signal tap_fifo_do    : std_logic_vector(7 downto 0);
signal tap_fifo_rdreq : std_logic;
signal tap_fifo_empty : std_logic;
signal tick_cnt       : std_logic_vector(16 downto 0);
signal wave_cnt       : std_logic_vector(15 downto 0);
signal wave_period    : std_logic;
signal skip_bytes     : std_logic;
signal playing        : std_logic;  -- 1 = tap or wav file is playing
signal bit_cnt        : std_logic_vector(2 downto 0);

type tzx_state_t is (
	TZX_HEADER,
	TZX_NEWBLOCK,
	TZX_PAUSE,
	TZX_PAUSE2,
	TZX_HWTYPE,
	TZX_TEXT,
	TZX_MESSAGE,
	TZX_ARCHIVE_INFO,
	TZX_TONE,
	TZX_PULSES,
	TZX_DATA,
	TZX_NORMAL,
	TZX_TURBO,
	TZX_PLAY_TONE,
	TZX_PLAY_SYNC1,
	TZX_PLAY_SYNC2,
	TZX_PLAY_TAPBLOCK,
	TZX_PLAY_TAPBLOCK2,
	TZX_PLAY_TAPBLOCK3,
	TZX_PLAY_TAPBLOCK4);

signal tzx_state: tzx_state_t;

signal tzx_offset     : std_logic_vector( 7 downto 0);
signal pause_len      : std_logic_vector(15 downto 0);
signal ms_counter     : std_logic_vector(15 downto 0);
signal pilot_l        : std_logic_vector(15 downto 0);
signal sync1_l        : std_logic_vector(15 downto 0);
signal sync2_l        : std_logic_vector(15 downto 0);
signal zero_l         : std_logic_vector(15 downto 0);
signal one_l          : std_logic_vector(15 downto 0);
signal pilot_pulses   : std_logic_vector(15 downto 0);
signal last_byte_bits : std_logic_vector( 3 downto 0);
signal data_len       : std_logic_vector(23 downto 0);
signal pulse_len      : std_logic_vector(15 downto 0);
signal end_period     : std_logic;
signal cass_motor_D   : std_logic;
signal motor_counter  : std_logic_vector(21 downto 0);

begin
-- for wav mode use large depth fifo (eg 512 x 32bits)
-- for tap mode fifo may be smaller (eg 16 x 32bits)
tap_fifo_inst : entity work.tap_fifo
port map(
	sclr	 => restart_tape,
	data	 => host_tap_in,
	clock	 => clk,
	rdreq	 => tap_fifo_rdreq,
	wrreq	 => host_tap_wrreq,
	q	     => tap_fifo_do,
	empty	 => tap_fifo_empty,
	full	 => tap_fifo_wrfull
);

process(clk)
begin
  if rising_edge(clk) then
	if restart_tape = '1' then

		tzx_offset <= (others => '0');
		tzx_state <= TZX_HEADER;
		pulse_len <= (others => '0');
		motor_counter <= (others => '0');
		wave_period <= '0';
		playing <= '0';

		tap_fifo_rdreq <='0';
		tap_fifo_error <='0'; -- run out of data

	else

		-- simulate tape motor momentum
		-- don't change the playing state if the motor is switched in 50 ms
		-- Opera Soft K17 protection needs this!
		cass_motor_D <= cass_motor;
		if cass_motor_D /= cass_motor then
			motor_counter <= CONV_STD_LOGIC_VECTOR(50*TZX_MS, motor_counter'length);
		elsif motor_counter /= 0 then
			if ce = '1' then motor_counter <= motor_counter - 1; end if;
		else
			playing <= cass_motor;
		end if;

		if playing = '0' then
			--cass_read <= '1';
		end if;	

		if pulse_len /= 0 then
			if ce = '1' then
				tick_cnt <= tick_cnt + 3500;
				if tick_cnt >= (TZX_MS - 3500) then
					tick_cnt <= tick_cnt - (TZX_MS - 3500);
					wave_cnt <= wave_cnt + 1;
					if wave_cnt = pulse_len then
						wave_cnt <= (others => '0');
						cass_read <= wave_period;
						wave_period <= not wave_period;
						if wave_period = end_period then
							pulse_len <= (others => '0');
						end if;
					end if;
				end if;
			end if;
		else
			tick_cnt <= (others => '0');
			wave_cnt <= (others => '0');
		end if;

		tap_fifo_rdreq <= '0';

		if playing = '1' and pulse_len = 0 then

			if tap_fifo_empty = '1' then
				tap_fifo_error <= '1';
			else
				tap_fifo_rdreq <= '1';
			end if;

			case tzx_state is
			when TZX_HEADER =>
				cass_read <= '1';
				tzx_offset <= tzx_offset + 1;
				if tzx_offset = x"0B" then -- skip 9 bytes, offset lags 2
					tzx_state <= TZX_NEWBLOCK;
				end if;

			when TZX_NEWBLOCK =>
				tzx_offset <= (others=>'0');
				ms_counter <= (others=>'0');
				if tap_fifo_empty = '0' then
					case tap_fifo_do is
					when x"20" => tzx_state <= TZX_PAUSE;
					when x"33" => tzx_state <= TZX_HWTYPE;
					when x"30" => tzx_state <= TZX_TEXT;
					when x"31" => tzx_state <= TZX_MESSAGE;
					when x"32" => tzx_state <= TZX_ARCHIVE_INFO;
					when x"21" => tzx_state <= TZX_TEXT; -- Group start
					when x"22" => null; -- Group end
					when x"12" => tzx_state <= TZX_TONE;
					when x"13" => tzx_state <= TZX_PULSES;
					when x"14" => tzx_state <= TZX_DATA;
					when x"10" => tzx_state <= TZX_NORMAL;
					when x"11" => tzx_state <= TZX_TURBO;
					when others => null;
					end case;
				end if;

			when TZX_PAUSE =>
				tzx_offset <= tzx_offset + 1;
				if tzx_offset = x"00" then 
					tap_fifo_rdreq <= '0';
					pause_len(7 downto 0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then
					pause_len(15 downto 8) <= tap_fifo_do;
					tzx_state <= TZX_PAUSE2;
				end if;

			when TZX_PAUSE2 =>
				tap_fifo_rdreq <= '0';
				if ms_counter /= 0 then if ce = '1' then ms_counter <= ms_counter - 1; end if;
				elsif pause_len /= 0 then
					pause_len <= pause_len - 1;
					ms_counter <= conv_std_logic_vector(TZX_MS, 16);
				else
					tap_fifo_rdreq <= '1';
					tzx_state <= TZX_NEWBLOCK;
				end if;

			when TZX_HWTYPE =>
				tzx_offset <= tzx_offset + 1;
				-- 0, 1-3, 1-3, ...
				if    tzx_offset = x"00" then data_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"03" then
					if data_len(7 downto 0) = x"01" then
						tzx_state <= TZX_NEWBLOCK;
					else
						data_len(7 downto 0) <= data_len(7 downto 0) - 1;
						tzx_offset <= x"01";
					end if;
				end if;

			when TZX_MESSAGE =>
				-- skip display time, then then same as TEXT DESRCRIPTION
				tzx_state <= TZX_TEXT;

			when TZX_TEXT =>
				tzx_offset <= tzx_offset + 1;
				if    tzx_offset = x"00" then data_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = data_len(7 downto 0) then
						tzx_state <= TZX_NEWBLOCK;
				end if;

			when TZX_ARCHIVE_INFO =>
				tzx_offset <= tzx_offset + 1;
				if    tzx_offset = x"00" then data_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then data_len(15 downto  8) <= tap_fifo_do;
				else
					tzx_offset <= x"02";
					data_len <= data_len - 1;
					if data_len = 1 then
						tzx_state <= TZX_NEWBLOCK;
					end if;
				end if;

			when TZX_TONE =>
				tzx_offset <= tzx_offset + 1;
				-- 0, 1, 2, 3, 4, 4, 4, ...
				if    tzx_offset = x"00" then pilot_l( 7 downto 0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then pilot_l(15 downto 8) <= tap_fifo_do;
				elsif tzx_offset = x"02" then pilot_pulses( 7 downto 0) <= tap_fifo_do;
				elsif tzx_offset = x"03" then
					tap_fifo_rdreq <= '0';
					pilot_pulses(15 downto 8) <= tap_fifo_do;
				else
					tzx_offset <= x"04";
					tap_fifo_rdreq <= '0';
					if pilot_pulses = 0 then
						tap_fifo_rdreq <= '1';
						tzx_state <= TZX_NEWBLOCK;
					else
						pilot_pulses <= pilot_pulses - 1;
						end_period <= wave_period;
						pulse_len <= pilot_l;
					end if;
				end if;

			when TZX_PULSES =>
				tzx_offset <= tzx_offset + 1;
				-- 0, 1-2+3, 1-2+3, ...
				if    tzx_offset = x"00" then data_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then one_l( 7 downto 0) <= tap_fifo_do;
				elsif tzx_offset = x"02" then
					tap_fifo_rdreq <= '0';
					end_period <= wave_period;
					pulse_len <= tap_fifo_do & one_l( 7 downto 0);
				elsif tzx_offset = x"03" then
					if data_len(7 downto 0) = x"01" then
						tzx_state <= TZX_NEWBLOCK;
					else
						data_len(7 downto 0) <= data_len(7 downto 0) - 1;
						tzx_offset <= x"01";
					end if;
				end if;

			when TZX_DATA =>
				tzx_offset <= tzx_offset + 1;
				if    tzx_offset = x"00" then zero_l ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then zero_l (15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"02" then one_l  ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"03" then one_l  (15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"04" then last_byte_bits <= tap_fifo_do(3 downto 0);
				elsif tzx_offset = x"05" then pause_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"06" then pause_len(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"07" then data_len ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"08" then data_len (15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"09" then
					tap_fifo_rdreq <= '0';
					data_len (23 downto 16) <= tap_fifo_do;
					tzx_state <= TZX_PLAY_TAPBLOCK;
				end if;

			when TZX_NORMAL =>
				tzx_offset <= tzx_offset + 1;
				if    tzx_offset = x"00" then pause_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then pause_len(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"02" then data_len ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"03" then
					tap_fifo_rdreq <= '0';
					data_len(15 downto  8) <= tap_fifo_do;
					data_len(23 downto 16) <= (others => '0');
					pilot_l <= conv_std_logic_vector(NORMAL_PILOT_LEN, 16);
					sync1_l <= conv_std_logic_vector(NORMAL_SYNC1_LEN, 16);
					sync2_l <= conv_std_logic_vector(NORMAL_SYNC2_LEN, 16);
					zero_l  <= conv_std_logic_vector(NORMAL_ZERO_LEN,  16);
					one_l   <= conv_std_logic_vector(NORMAL_ONE_LEN,   16);
					pilot_pulses <= conv_std_logic_vector(NORMAL_PILOT_PULSES, 16);
					last_byte_bits <= "1000";
					tzx_state <= TZX_PLAY_TONE;
				end if;

			when TZX_TURBO =>
				tzx_offset <= tzx_offset + 1;
				if    tzx_offset = x"00" then pilot_l( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"01" then pilot_l(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"02" then sync1_l( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"03" then sync1_l(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"04" then sync2_l( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"05" then sync2_l(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"06" then zero_l ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"07" then zero_l (15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"08" then one_l  ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"09" then one_l  (15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"0A" then pilot_pulses( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"0B" then pilot_pulses(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"0C" then last_byte_bits <= tap_fifo_do(3 downto 0);
				elsif tzx_offset = x"0D" then pause_len( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"0E" then pause_len(15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"0F" then data_len ( 7 downto  0) <= tap_fifo_do;
				elsif tzx_offset = x"10" then data_len (15 downto  8) <= tap_fifo_do;
				elsif tzx_offset = x"11" then
					tap_fifo_rdreq <= '0';
					data_len (23 downto 16) <= tap_fifo_do;
					tzx_state <= TZX_PLAY_TONE;
				end if;

			when TZX_PLAY_TONE =>
				tap_fifo_rdreq <= '0';
				end_period <= not wave_period;
				pulse_len <= pilot_l;
				if pilot_pulses /= 0 then
					pilot_pulses <= pilot_pulses - 1;
				else
					tzx_state <= TZX_PLAY_SYNC1;
				end if;

			when TZX_PLAY_SYNC1 =>
				tap_fifo_rdreq <= '0';
				end_period <= wave_period;
				pulse_len <= sync1_l;
				tzx_state <= TZX_PLAY_SYNC2;

			when TZX_PLAY_SYNC2 =>
				tap_fifo_rdreq <= '0';
				end_period <= wave_period;
				pulse_len <= sync2_l;
				tzx_state <= TZX_PLAY_TAPBLOCK;

			when TZX_PLAY_TAPBLOCK =>
				tap_fifo_rdreq <= '0';
				bit_cnt <= "111";
				tzx_state <= TZX_PLAY_TAPBLOCK2;

			when TZX_PLAY_TAPBLOCK2 =>
				tap_fifo_rdreq <= '0';
				bit_cnt <= bit_cnt - 1;
				if bit_cnt = "000" then 
					data_len <= data_len - 1;
					tzx_state <= TZX_PLAY_TAPBLOCK3;
				end if;
				end_period <= not wave_period;
				if tap_fifo_do(CONV_INTEGER(bit_cnt)) = '0' then
					pulse_len <= zero_l;
				else
					pulse_len <= one_l;
				end if;

			when TZX_PLAY_TAPBLOCK3 =>
				if data_len = 0 then
					tzx_state <= TZX_PAUSE2;
				else
					tzx_state <= TZX_PLAY_TAPBLOCK4;
				end if;

			when TZX_PLAY_TAPBLOCK4 =>
				tap_fifo_rdreq <= '0';
				tzx_state <= TZX_PLAY_TAPBLOCK2;

			when others => null;
			end case;

		end if; -- play tzx

	end if;
  end if; -- clk
end process;

end struct;
