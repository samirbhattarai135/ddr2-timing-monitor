-- Drives every DDR2 command onto the pins, per Table 37 of the Micron
-- datasheet, and requires ddr2_cmd_decode to return the matching transition
-- id. Also checks that NOP/DESELECT are silent and LOAD MODE is flagged.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.net_pkg.all;

entity tb_decode is
end entity;

architecture sim of tb_decode is
  signal clk, rst : std_logic := '0';
  signal cke, cs_n, ras_n, cas_n, we_n : std_logic := '1';
  signal a10 : std_logic := '0';
  signal ba : std_logic_vector(BA_BITS - 1 downto 0) := (others => '0');
  signal cmd_valid, unmodelled : std_logic;
  signal cmd_t : natural range 0 to N_T - 1;
begin
  dut : entity work.ddr2_cmd_decode
    port map (clk, rst, cke, cs_n, ras_n, cas_n, we_n, a10, ba, cmd_valid, cmd_t, unmodelled);

  process
    variable checks : natural := 0;

    procedure drive(k, cs, r, c, w, a : std_logic; b : natural) is
    begin
      cke <= k; cs_n <= cs; ras_n <= r; cas_n <= c; we_n <= w; a10 <= a;
      ba <= std_logic_vector(to_unsigned(b, BA_BITS));
      wait for 1 ns;
    end procedure;

    procedure tick is
    begin
      clk <= '1'; wait for 5 ns; clk <= '0'; wait for 4 ns;
    end procedure;

    procedure expect(c : ddr2_cmd_t; b : natural; what : string) is
    begin
      assert cmd_valid = '1' and unmodelled = '0' and cmd_t = T_ID(c)(b)
        report "decode failed: " & what severity failure;
      checks := checks + 1;
      tick;
    end procedure;

    procedure expect_silent(flag : std_logic; what : string) is
    begin
      assert cmd_valid = '0' and unmodelled = flag report "decode failed: " & what severity failure;
      checks := checks + 1;
      tick;
    end procedure;
  begin
    rst <= '1'; tick; rst <= '0';
    for b in 0 to N_BANKS - 1 loop
      drive('1', '0', '0', '1', '1', '0', b); expect(ACT, b, "ACT");
      drive('1', '0', '1', '0', '1', '0', b); expect(RD, b, "RD");
      drive('1', '0', '1', '0', '1', '1', b); expect(RDA, b, "RDA");
      drive('1', '0', '1', '0', '0', '0', b); expect(WR, b, "WR");
      drive('1', '0', '1', '0', '0', '1', b); expect(WRA, b, "WRA");
      drive('1', '0', '0', '1', '0', '0', b); expect(PRE, b, "PRE");
    end loop;
    drive('1', '0', '0', '1', '0', '1', 0); expect(PREA, 0, "PREA");
    drive('1', '0', '0', '0', '1', '0', 0); expect(REF, 0, "REF");
    drive('1', '0', '1', '1', '1', '0', 0); expect_silent('0', "NOP");
    drive('1', '1', '0', '0', '0', '0', 0); expect_silent('0', "DESELECT");
    drive('1', '0', '0', '0', '0', '0', 0); expect_silent('1', "LOAD MODE");
    -- Power-down entry via DESELECT, held, exit via NOP.
    drive('0', '1', '1', '1', '1', '0', 0); expect(PDE, 0, "PDE");
    drive('0', '1', '1', '1', '1', '0', 0); expect_silent('0', "CKE held low");
    drive('1', '0', '1', '1', '1', '0', 0); expect(PDX, 0, "PDX");
    -- Self refresh: entry is a REFRESH with CKE falling; exit is CKE rising.
    drive('0', '0', '0', '0', '1', '0', 0); expect(SRE, 0, "SRE");
    drive('0', '1', '1', '1', '1', '0', 0); expect_silent('0', "in self refresh");
    drive('1', '1', '1', '1', '1', '0', 0); expect(SRX, 0, "SRX");
    -- A command on a CKE edge is malformed.
    drive('0', '0', '0', '1', '1', '0', 0); expect_silent('1', "ACT on CKE falling edge");
    report "RESULT decode checks=" & integer'image(checks) & " banks=" & integer'image(N_BANKS);
    std.env.finish;
  end process;
end architecture;
