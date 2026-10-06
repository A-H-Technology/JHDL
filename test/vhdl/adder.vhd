library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-- Registered 8-bit adder: Y <= A + B on every rising edge, cleared on reset.
entity adder is
    port (
        A   : in  unsigned(7 downto 0);
        B   : in  unsigned(7 downto 0);
        Y   : out unsigned(7 downto 0);
        CLK : in  std_logic;
        RST : in  std_logic
    );
end entity;

architecture RTL of adder is
begin
    process (CLK)
    begin
        if rising_edge(CLK) then
            if RST = '1' then
                Y <= (others => '0');
            else
                Y <= A + B;
            end if;
        end if;
    end process;
end architecture;
