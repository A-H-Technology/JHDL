library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Only analyzed, never simulated: exercises what DUT(file) has to read back.
entity Widths is
    generic (
        WIDTH : natural := 4;
        FLAG  : boolean := true
    );
    port (
	A, Bb : in  unsigned(WIDTH-1 downto 0);
        Clk   : in  std_logic;
        Rst   : in  std_logic;
        Wide  : out std_logic_vector(2*(WIDTH+1) downto 0);
        Up    : inout signed(0 to WIDTH)
    );
end entity;

architecture empty of Widths is
begin
end architecture;
