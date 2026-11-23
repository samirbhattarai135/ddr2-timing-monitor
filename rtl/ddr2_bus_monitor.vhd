-- DDR2 command-bus monitor: pins in, one violation report out.
-- ddr2_cmd_decode turns the pins into a transition id; petri_monitor judges it
-- against the DRAMPyML net. first_arc is the lowest-numbered blocking arc
-- (names in build/<config>/arcs.tsv).

library ieee;
use ieee.std_logic_1164.all;
use work.net_pkg.all;

entity ddr2_bus_monitor is
  port (
    clk, rst : in std_logic;
    cke, cs_n, ras_n, cas_n, we_n, a10 : in std_logic;
    ba : in std_logic_vector(BA_BITS - 1 downto 0);
    violation  : out std_logic;              -- one cycle after the offending command
    first_arc  : out natural range 0 to N_ARC - 1;
    unmodelled : out std_logic;              -- LOAD MODE or malformed CKE edge, unregistered
    violations : out natural
  );
end entity;

architecture rtl of ddr2_bus_monitor is
  signal cmd_valid, v_valid, v_legal : std_logic;
  signal cmd_t : natural range 0 to N_T - 1;
  signal v_arcs : std_logic_vector(0 to N_ARC - 1);
begin
  decode : entity work.ddr2_cmd_decode
    port map (clk, rst, cke, cs_n, ras_n, cas_n, we_n, a10, ba, cmd_valid, cmd_t, unmodelled);

  monitor : entity work.petri_monitor
    port map (clk, rst, cmd_valid, cmd_t, v_valid, v_legal, v_arcs, violations);

  violation <= v_valid and not v_legal;

  process (all)
  begin
    first_arc <= 0;
    for i in v_arcs'reverse_range loop
      if v_arcs(i) = '1' then
        first_arc <= i;
      end if;
    end loop;
  end process;
end architecture;
