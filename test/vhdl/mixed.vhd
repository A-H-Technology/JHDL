library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Registered DUT with one port of each type the reader/writer handles.
entity mixed is
    generic (
        OFFSET : integer := 0
    );
    port (
        S   : in  signed(7 downto 0);
        V   : in  std_logic_vector(3 downto 0);
        EN  : in  boolean;
        N   : in  integer;
        SO  : out signed(7 downto 0);
        VO  : out std_logic_vector(3 downto 0);
        BO  : out boolean;
        NO  : out integer;
        CLK : in  std_logic;
        RST : in  std_logic
    );
end entity;

architecture RTL of mixed is
begin
    process (CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                SO <= (others => '0');
                VO <= (others => '0');
                BO <= false;
                NO <= 0;
            else
                SO <= S + OFFSET;
                VO <= not V;
                BO <= not EN;
                NO <= N * 2;
            end if;
        end if;
    end process;
end architecture;
