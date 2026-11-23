-- Differential testbench: replays a trace file through petri_monitor and
-- requires its verdict on every command to equal the oracle's, arc for arc.
--
-- Trace file lines (written by tools/tracegen.py):
--   R                                   reset the monitor; time restarts at 0
--   C <time> <tid> <legal> <n> <arc>... command at cycle <time>; the oracle's
--                                       verdict and the ids of its <n> blocking arcs
-- Any disagreement stops the simulation with a failure.

library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;
use work.net_pkg.all;

entity tb_monitor is
  generic (TRACE_FILE : string := "trace.txt");
end entity;

architecture sim of tb_monitor is
  signal clk, rst, cmd_valid : std_logic := '0';
  signal cmd_t : natural range 0 to N_T - 1 := 0;
  signal verdict_valid, verdict_legal : std_logic;
  signal verdict_arcs : std_logic_vector(0 to N_ARC - 1);
  signal violations : natural;
begin
  dut : entity work.petri_monitor
    port map (clk, rst, cmd_valid, cmd_t, verdict_valid, verdict_legal, verdict_arcs, violations);

  process
    file f : text;
    variable l : line;
    variable kind : character;
    variable time_v, tid, legal, n, arc_id : integer;
    variable cycle : natural := 0;
    variable expect : std_logic_vector(0 to N_ARC - 1);
    variable n_cmd, n_legal, n_illegal, n_traces, n_cycles : natural := 0;
    variable illegal_in_trace : natural := 0;

    procedure tick is
    begin
      clk <= '1';
      wait for 5 ns;
      clk <= '0';
      wait for 5 ns;
    end procedure;

    impure function arc_list(v : std_logic_vector) return string is
      variable s : line;
    begin
      write(s, string'(""));
      for i in v'range loop
        if v(i) = '1' then
          write(s, integer'image(i) & " ");
        end if;
      end loop;
      return s.all;
    end function;
  begin
    file_open(f, TRACE_FILE, read_mode);
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0;
      read(l, kind);
      if kind = 'R' then
        rst <= '1';
        cmd_valid <= '0';
        tick;
        rst <= '0';
        cycle := 0;
        illegal_in_trace := 0;
        n_traces := n_traces + 1;
      else
        read(l, time_v);
        read(l, tid);
        read(l, legal);
        read(l, n);
        expect := (others => '0');
        for k in 1 to n loop
          read(l, arc_id);
          expect(arc_id) := '1';
        end loop;
        assert time_v >= cycle report "trace time goes backwards" severity failure;
        cmd_valid <= '0';
        while cycle < time_v loop
          tick;
          cycle := cycle + 1;
          n_cycles := n_cycles + 1;
        end loop;
        cmd_valid <= '1';
        cmd_t <= tid;
        tick;
        cycle := cycle + 1;
        n_cycles := n_cycles + 1;
        cmd_valid <= '0';

        n_cmd := n_cmd + 1;
        if legal = 1 then
          n_legal := n_legal + 1;
        else
          n_illegal := n_illegal + 1;
          illegal_in_trace := illegal_in_trace + 1;
        end if;
        assert verdict_valid = '1' report "no verdict" severity failure;
        assert (verdict_legal = '1') = (legal = 1) and verdict_arcs = expect
          report "MISMATCH trace " & integer'image(n_traces) & " time " & integer'image(time_v)
               & " tid " & integer'image(tid) & ": oracle legal=" & integer'image(legal)
               & " arcs [" & arc_list(expect) & "], monitor legal=" & std_logic'image(verdict_legal)
               & " arcs [" & arc_list(verdict_arcs) & "]"
          severity failure;
        assert violations = illegal_in_trace report "violation counter disagrees" severity failure;
      end if;
    end loop;
    report "RESULT config=" & CONFIG_NAME & " traces=" & integer'image(n_traces)
         & " commands=" & integer'image(n_cmd) & " legal=" & integer'image(n_legal)
         & " illegal=" & integer'image(n_illegal) & " cycles=" & integer'image(n_cycles)
         & " mismatches=0";
    std.env.finish;
  end process;
end architecture;
