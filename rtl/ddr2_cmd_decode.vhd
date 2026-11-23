-- Decodes the DDR2 command pins into the monitor's transition id.
--
-- Encoding from Micron 1Gb DDR2 datasheet, Table 37 (p. 73), sampled on the
-- rising edge of CK:
--   CKE prev/cur  CS# RAS# CAS# WE#  A10
--   H H           L   L    L    L    -    LOAD MODE       (not in the net: flagged)
--   H H           L   L    L    H    -    REFRESH
--   H H           L   L    H    L    L/H  PRECHARGE bank / PRECHARGE ALL
--   H H           L   L    H    H    -    ACTIVATE
--   H H           L   H    L    L    L/H  WRITE / WRITE with auto precharge
--   H H           L   H    L    H    L/H  READ / READ with auto precharge
--   H L           L   L    L    H    -    SELF REFRESH entry
--   H L           H, or L H H H      -    power-down entry
--   L H           H, or L H H H      -    self-refresh exit if in self refresh,
--                                         else power-down exit
-- NOP (L H H H) and DESELECT (CS# high) with CKE steady are not commands.
-- Any other pattern on a CKE edge is flagged as `unmodelled`.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.net_pkg.all;

entity ddr2_cmd_decode is
  port (
    clk, rst    : in  std_logic;
    cke, cs_n, ras_n, cas_n, we_n, a10 : in std_logic;
    ba          : in  std_logic_vector(BA_BITS - 1 downto 0);
    cmd_valid   : out std_logic;
    cmd_t       : out natural range 0 to N_T - 1;
    unmodelled  : out std_logic   -- LOAD MODE or a malformed CKE edge
  );
end entity;

architecture rtl of ddr2_cmd_decode is
  signal cke_prev : std_logic := '1';
  signal in_sref  : std_logic := '0';
begin
  process (all)
    variable c    : ddr2_cmd_t;
    variable hit  : boolean;
    variable odd  : boolean;
    variable bank : natural;
    variable pins : std_logic_vector(2 downto 0);
    variable idle : boolean;  -- DESELECT or NOP
  begin
    hit := false;
    odd := false;
    c := ACT;
    pins := ras_n & cas_n & we_n;
    idle := cs_n = '1' or pins = "111";
    if cke_prev = '1' and cke = '1' then
      if cs_n = '0' then
        hit := true;
        case pins is
          when "000" => hit := false; odd := true;  -- LOAD MODE
          when "001" => c := REF;
          when "010" => if a10 = '1' then c := PREA; else c := PRE; end if;
          when "011" => c := ACT;
          when "100" => if a10 = '1' then c := WRA; else c := WR; end if;
          when "101" => if a10 = '1' then c := RDA; else c := RD; end if;
          when others => hit := false;  -- NOP
        end case;
      end if;
    elsif cke_prev = '1' and cke = '0' then
      if cs_n = '0' and pins = "001" then
        hit := true; c := SRE;
      elsif idle then
        hit := true; c := PDE;
      else
        odd := true;
      end if;
    elsif cke_prev = '0' and cke = '1' then
      if idle then
        hit := true;
        if in_sref = '1' then c := SRX; else c := PDX; end if;
      else
        odd := true;
      end if;
    end if;

    bank := to_integer(unsigned(ba));
    if bank >= N_BANKS then
      bank := 0;
    end if;
    -- Plain ifs rather than sequential "when" assignments, for older Vivado parsers.
    if hit then cmd_valid <= '1'; else cmd_valid <= '0'; end if;
    if odd then unmodelled <= '1'; else unmodelled <= '0'; end if;
    cmd_t <= T_ID(c)(bank);
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cke_prev <= '1';
        in_sref <= '0';
      else
        cke_prev <= cke;
        if cke_prev = '1' and cke = '0' and cs_n = '0' and std_logic_vector'(ras_n & cas_n & we_n) = "001" then
          in_sref <= '1';
        elsif cke_prev = '0' and cke = '1' then
          in_sref <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
