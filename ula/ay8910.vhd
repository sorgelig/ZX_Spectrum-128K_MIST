-------------------------------------------------------------------[01.07.2015]
-- AY3-8910
-------------------------------------------------------------------------------
-- 15.10.2011	первая версия

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
 
entity ay8910 is
   port(
      CLK_I   	: in  std_logic;                   	-- System Clock
      EN_I   	: in  std_logic;                    	-- PSG Clock
      RESET_I 	: in  std_logic;                    	-- Chip RESET_I (set all Registers to '0', active hi)
      BDIR_I  	: in  std_logic;                    	-- Bus Direction (0 - read , 1 - write)
      CS_I    	: in  std_logic;                    	-- Chip Select (active hi)
      BC_I    	: in  std_logic;                    	-- Bus control
      DATA_I    : in  std_logic_vector(7 downto 0); 	-- Data In
      DATA_O    : out std_logic_vector(7 downto 0); 	-- Data Out
      CH_A_O 	: out std_logic_vector(7 downto 0); 	-- PSG Output channel A
      CH_B_O 	: out std_logic_vector(7 downto 0); 	-- PSG Output channel B
      CH_C_O 	: out std_logic_vector(7 downto 0)  	-- PSG Output channel C
   );
end ay8910;
 
architecture rtl of ay8910 is
 
   signal ClockDiv   : unsigned (3 downto 0);		-- Divide EN_I
 
-- AY Registers
   signal Period_A   : std_logic_vector (11 downto 0);	-- Channel A Tone Period (R1:R0)
   signal Period_B   : std_logic_vector (11 downto 0);	-- Channel B Tone Period (R3:R2)
   signal Period_C   : std_logic_vector (11 downto 0);	-- Channel C Tone Period (R5:R4)
   signal Period_N   : std_logic_vector (4 downto 0);	-- Noise Period (R6)
   signal Enable     : std_logic_vector (7 downto 0);	-- Enable (R7)
   signal Volume_A   : std_logic_vector (4 downto 0);	-- Channel A Amplitude (R10)
   signal Volume_B   : std_logic_vector (4 downto 0);	-- Channel B Amplitude (R11)
   signal Volume_C   : std_logic_vector (4 downto 0);	-- Channel C Amplitude (R12)
   signal Period_E   : std_logic_vector (15 downto 0);	-- Envelope Period (R14:R13)
   signal Shape      : std_logic_vector (3 downto 0);	-- Envelope Shape/Cycle (R15)
--   signal Port_A     : std_logic_vector (7 downto 0);	-- I/O Port A Data Store (R16)
--   signal Port_B     : std_logic_vector (7 downto 0);	-- I/O Port B Data Store (R17)
--
   signal Address    : std_logic_vector (3 downto 0);	-- Selected Register
 
   alias  Continue   : std_logic is Shape(3);			-- Envelope Control
   alias  Attack     : std_logic is Shape(2);
   alias  Alternate  : std_logic is Shape(1);
   alias  Hold       : std_logic is Shape(0);
 
   signal Reset_Req  : std_logic;						-- Envelope RESET_I Required
   signal Reset_Ack  : std_logic;						-- Envelope RESET_I Acknoledge
   signal Volume_E   : std_logic_vector (3 downto 0);   -- Envelope Volume
 
   signal Freq_A     : std_logic;                       -- Tone Generator A Output
   signal Freq_B     : std_logic;                       -- Tone Generator B Output
   signal Freq_C     : std_logic;                       -- Tone Generator C Output
   signal Freq_N     : std_logic;                       -- Noise Generator Output
 
   function VolumeTable (value : std_logic_vector(3 downto 0)) return std_logic_vector is
      variable result : std_logic_vector (7 downto 0);
   begin
      case value is 									-- Volume Table
         when "1111"  => result := "11111111";
         when "1110"  => result := "10110100";
         when "1101"  => result := "01111111";
         when "1100"  => result := "01011010";
         when "1011"  => result := "00111111";
         when "1010"  => result := "00101101";
         when "1001"  => result := "00011111";
         when "1000"  => result := "00010110";
         when "0111"  => result := "00001111";
         when "0110"  => result := "00001011";
         when "0101"  => result := "00000111";
         when "0100"  => result := "00000101";
         when "0011"  => result := "00000011";
         when "0010"  => result := "00000010";
         when "0001"  => result := "00000001";
         when "0000"  => result := "00000000";
         when others => null;
      end case;
   return result;
   end VolumeTable;
 
begin
 
-- Write to AY
process (RESET_I , CLK_I)
begin
   if RESET_I = '1' then
      Address   <= "0000";
      Period_A  <= "000000000000";
      Period_B  <= "000000000000";
      Period_C  <= "000000000000";
      Period_N  <= "00000";
      Enable    <= "00000000";
      Volume_A  <= "00000";
      Volume_B  <= "00000";
      Volume_C  <= "00000";
      Period_E  <= "0000000000000000";
      Shape     <= "0000";
--      Port_A    <= "00000000";
--      Port_B    <= "00000000";
      Reset_Req <= '0';
   elsif rising_edge(CLK_I) then
      if CS_I = '1' and BDIR_I = '1' then
         if BC_I = '1' then
            Address <= DATA_I (3 downto 0);						-- Latch Address
         else
            case Address is									-- Latch Registers
               when "0000" => Period_A (7 downto 0)   <= DATA_I;
               when "0001" => Period_A (11 downto 8)  <= DATA_I (3 downto 0);
               when "0010" => Period_B (7 downto 0)   <= DATA_I;
               when "0011" => Period_B (11 downto 8)  <= DATA_I (3 downto 0);
               when "0100" => Period_C (7 downto 0)   <= DATA_I;
               when "0101" => Period_C (11 downto 8)  <= DATA_I (3 downto 0);
               when "0110" => Period_N                <= DATA_I (4 downto 0);
               when "0111" => Enable                  <= DATA_I;
               when "1000" => Volume_A                <= DATA_I (4 downto 0);
               when "1001" => Volume_B                <= DATA_I (4 downto 0);
               when "1010" => Volume_C                <= DATA_I (4 downto 0);
               when "1011" => Period_E (7 downto 0)   <= DATA_I;
               when "1100" => Period_E (15 downto 8)  <= DATA_I;
               when "1101" => Shape                   <= DATA_I (3 downto 0);
                              Reset_Req               <= not Reset_Ack; -- RESET_I Envelope Generator
--               when "1110" => Port_A                  <= DATA_I;
--               when "1111" => Port_B                  <= DATA_I;
               when others => null;
            end case;
         end if;
      end if;
   end if;
end process;
 
-- Read from AY
DATA_O	<=	Period_A (7 downto 0)			when Address = "0000" and CS_I = '1' else
		"0000" & Period_A (11 downto 8)	when Address = "0001" and CS_I = '1' else
		Period_B (7 downto 0)   		when Address = "0010" and CS_I = '1' else
		"0000" & Period_B (11 downto 8) when Address = "0011" and CS_I = '1' else
		Period_C (7 downto 0)   		when Address = "0100" and CS_I = '1' else
		"0000" & Period_C (11 downto 8) when Address = "0101" and CS_I = '1' else
		"000" & Period_N                when Address = "0110" and CS_I = '1' else
        Enable                  		when Address = "0111" and CS_I = '1' else
        "000" & Volume_A                when Address = "1000" and CS_I = '1' else
        "000" & Volume_B                when Address = "1001" and CS_I = '1' else
        "000" & Volume_C                when Address = "1010" and CS_I = '1' else
		Period_E (7 downto 0)   		when Address = "1011" and CS_I = '1' else
		Period_E (15 downto 8)  		when Address = "1100" and CS_I = '1' else
		"0000" & Shape                  when Address = "1101" and CS_I = '1' else
		"11111111";
 
-- Divide EN_I
process (RESET_I, CLK_I)
begin
   if RESET_I = '1' then
      ClockDiv <= "0000";
   elsif rising_edge(CLK_I) then
      if EN_I = '1' then
         ClockDiv <= ClockDiv - 1;
      end if;
   end if;
end process;
 
-- Tone Generator
process (RESET_I, CLK_I)
   variable Counter_A   : unsigned (11 downto 0);
   variable Counter_B   : unsigned (11 downto 0);
   variable Counter_C   : unsigned (11 downto 0);
begin
   if RESET_I = '1' then
      Counter_A   := "000000000000";
      Counter_B   := "000000000000";
      Counter_C   := "000000000000";
      Freq_A      <= '0';
      Freq_B      <= '0';
      Freq_C      <= '0';
   elsif rising_edge(CLK_I) then
      if ClockDiv(2 downto 0) = "000" and EN_I = '1' then
 
         -- Channel A Counter
         if (Counter_A /= X"000") then
            Counter_A := Counter_A - 1;
         elsif (Period_A /= X"000") then
            Counter_A := unsigned(Period_A) - 1;
         end if;
         if (Counter_A = X"000") then
            Freq_A <= not Freq_A;
         end if;
 
         -- Channel B Counter
         if (Counter_B /= X"000") then
            Counter_B := Counter_B - 1;
         elsif (Period_B /= X"000") then
            Counter_B := unsigned(Period_B) - 1;
         end if;
         if (Counter_B = X"000") then
            Freq_B <= not Freq_B;
         end if;
 
         -- Channel C Counter
         if (Counter_C /= X"000") then
            Counter_C := Counter_C - 1;
         elsif (Period_C /= X"000") then
            Counter_C := unsigned(Period_C) - 1;
         end if;
         if (Counter_C = X"000") then
            Freq_C <= not Freq_C;
         end if;
 
      end if;
   end if;
end process;
 
-- Noise Generator
process (RESET_I, CLK_I)
   variable NoiseShift : unsigned (16 downto 0);
   variable Counter_N  : unsigned (4 downto 0);
begin
   if RESET_I = '1' then
      Counter_N   := "00000";
      NoiseShift  := "00000000000000001";
   elsif rising_edge(CLK_I) then
     if ClockDiv(2 downto 0) = "000" and EN_I = '1' then
         if (Counter_N /= "00000") then
            Counter_N := Counter_N - 1;
         elsif (Period_N /= "00000") then
            Counter_N := unsigned(Period_N) - 1;
         end if;
         if Counter_N = "00000" then
            NoiseShift := (NoiseShift(0) xor NoiseShift(2)) & NoiseShift(16 downto 1);
         end if;
         Freq_N <= NoiseShift(0);
      end if;
   end if;
end process;
 
-- Envelope Generator
process (RESET_I , CLK_I)
   variable EnvCounter  : unsigned(15 downto 0);
   variable EnvWave     : unsigned(4 downto 0);
begin
   if RESET_I = '1' then
      EnvCounter  := "0000000000000000";
      EnvWave     := "11111";
      Volume_E    <= "0000";
      Reset_Ack   <= '0';
   elsif rising_edge(CLK_I) then
      if ClockDiv = "0000" and EN_I = '1' then
         -- Envelope Period Counter 
         if (EnvCounter /= X"0000" and Reset_Req = Reset_Ack) then 
            EnvCounter := EnvCounter - 1;
         elsif (Period_E /= X"0000") then
            EnvCounter := unsigned(Period_E) - 1;
         end if;
 
         -- Envelope Phase Counter
         if (Reset_Req /= Reset_Ack) then
            EnvWave := (others => '1');
         elsif (EnvCounter = X"0000" and (EnvWave(4) = '1' or (Hold = '0' and Continue = '1'))) then
            EnvWave := EnvWave - 1;
         end if;
 
         -- Envelope Amplitude Counter
         for I in 3 downto 0 loop
            if (EnvWave(4) = '0' and Continue = '0') then
               Volume_E(I) <= '0';
            elsif (EnvWave(4) = '1' or (Alternate xor Hold) = '0') then
               Volume_E(I) <= EnvWave(I) xor Attack;
            else
              Volume_E(I) <= EnvWave(I) xor Attack xor '1';
            end if;
         end loop;
         Reset_Ack <= Reset_Req;
       end if;
   end if;
end process;
 
-- Mixer
process (RESET_I , CLK_I)
begin
   if RESET_I = '1' then
      CH_A_O <= "00000000";
      CH_B_O <= "00000000";
      CH_C_O <= "00000000";
   elsif rising_edge(CLK_I) then
      if EN_I = '1' then
         if (((Enable(0) or Freq_A) and (Enable(3) or Freq_N)) = '0') then
            CH_A_O <= "00000000";
         elsif (Volume_A(4) = '0') then
            CH_A_O <= VolumeTable(Volume_A(3 downto 0));
         else
            CH_A_O <= VolumeTable(Volume_E);
         end if;
 
         if (((Enable(1) or Freq_B) and (Enable(4) or Freq_N)) = '0') then
            CH_B_O <= "00000000";
         elsif (Volume_B(4) = '0') then
            CH_B_O <= VolumeTable(Volume_B(3 downto 0));
         else
            CH_B_O <= VolumeTable(Volume_E);
         end if;
 
         if (((Enable(2) or Freq_C) and (Enable(5) or Freq_N)) = '0') then
            CH_C_O <= "00000000";
         elsif (Volume_C(4) = '0') then
            CH_C_O <= VolumeTable(Volume_C(3 downto 0));
         else
            CH_C_O <= VolumeTable(Volume_E);
         end if;
      end if;
   end if;
end process;
 
end rtl;