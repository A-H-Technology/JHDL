library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Counts the cycles EN is high; DONE goes high once COUNT reaches LIMIT.
entity counter is
    generic (
        LIMIT : natural := 255
    );
    port (
        EN    : in  std_logic;
        COUNT : out unsigned(7 downto 0);
        DONE  : out std_logic;
        CLK   : in  std_logic;
        RST   : in  std_logic
    );
end entity;

architecture RTL of counter is
    signal n : unsigned(7 downto 0);
begin
    process (CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                n <= (others => '0');
            elsif EN = '1' then
                n <= n + 1;
            end if;
        end if;
    end process;

    COUNT <= n;
    DONE  <= '1' when n = LIMIT else '0';
end architecture;
