-- Executes the DRAMPyML timed Petri net in hardware, one clock per tCK.
--
-- Each cycle at most one command arrives as a transition id. The monitor
-- checks every arc into that transition (net_pkg.ARCS) against the current
-- marking and ages, reports the result one cycle later, and fires the
-- transition only if it was legal. An illegal command is flagged and ignored,
-- the same policy as tools/oracle.py.
--
-- State:
--   t_age(t)   cycles since transition t last fired, saturating at AGE_MAX
--              ("never fired"). Carries every CustomArc timing rule.
--   count(p)   tokens in place p.
--   tok(p)(i)  ages of the tokens in a timed place, oldest first. Only places
--              read by a TimedArc (the four-activate pool, the command bus)
--              need them.

library ieee;
use ieee.std_logic_1164.all;
use work.net_pkg.all;

entity petri_monitor is
  port (
    clk           : in  std_logic;
    rst           : in  std_logic;
    cmd_valid     : in  std_logic;
    cmd_t         : in  natural range 0 to N_T - 1;
    -- One cycle after a command:
    verdict_valid : out std_logic;
    verdict_legal : out std_logic;
    verdict_arcs  : out std_logic_vector(0 to N_ARC - 1);  -- '1' = this arc blocked it
    violations    : out natural
  );
end entity;

architecture rtl of petri_monitor is
  subtype age_t is natural range 1 to AGE_MAX;
  type age_array_t is array (natural range <>) of age_t;
  type tok_fifo_t is array (0 to TOK_MAX - 1) of age_t;
  type tok_array_t is array (0 to N_P - 1) of tok_fifo_t;
  type count_array_t is array (0 to N_P - 1) of natural range 0 to TOK_MAX;

  function initial_counts return count_array_t is
    variable c : count_array_t;
  begin
    for p in c'range loop
      c(p) := PLACE_INIT(p);
    end loop;
    return c;
  end function;

  -- Initial tokens are "infinitely old", like upstream Token(-2**32).
  constant TOK_RESET   : tok_array_t := (others => (others => AGE_MAX));
  constant COUNT_RESET : count_array_t := initial_counts;

  function older(a : age_t) return age_t is
  begin
    if a = AGE_MAX then
      return AGE_MAX;
    end if;
    return a + 1;
  end function;

  signal t_age : age_array_t(0 to N_T - 1) := (others => AGE_MAX);
  signal count : count_array_t := COUNT_RESET;
  signal tok   : tok_array_t := TOK_RESET;
  signal n_viol : natural := 0;
begin
  violations <= n_viol;

  process (clk)
    variable blocked : std_logic_vector(0 to N_ARC - 1);
    variable ready   : natural;
    variable c       : count_array_t;
    variable q       : tok_array_t;
    variable a       : age_array_t(0 to N_T - 1);
    variable arc     : arc_t;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        t_age <= (others => AGE_MAX);
        count <= COUNT_RESET;
        tok <= TOK_RESET;
        n_viol <= 0;
        verdict_valid <= '0';
        verdict_legal <= '0';
        verdict_arcs <= (others => '0');
      else
        -- 1. Which arcs into this transition block it?
        blocked := (others => '0');
        if cmd_valid = '1' then
          for i in ARCS'range loop
            arc := ARCS(i);
            if arc.dst = cmd_t and arc.kind /= ARC_OUT then
              case arc.kind is
                when ARC_IN =>
                  if count(arc.src) < arc.weight then blocked(i) := '1'; end if;
                when ARC_INHIBIT =>
                  if count(arc.src) >= arc.weight then blocked(i) := '1'; end if;
                when ARC_TIMED =>
                  ready := 0;
                  for k in 0 to TOK_MAX - 1 loop
                    if k < count(arc.src) and tok(arc.src)(k) >= arc.bound then
                      ready := ready + 1;
                    end if;
                  end loop;
                  if ready < arc.weight then blocked(i) := '1'; end if;
                when ARC_CUSTOM =>
                  if t_age(arc.src) < arc.bound then blocked(i) := '1'; end if;
                when others =>
                  null;  -- a reset arc never blocks
              end case;
            end if;
          end loop;
        end if;

        -- 2. Time advances for everything.
        c := count;
        for t in a'range loop
          a(t) := older(t_age(t));
        end loop;
        for p in q'range loop
          for k in 0 to TOK_MAX - 1 loop
            q(p)(k) := older(tok(p)(k));
          end loop;
        end loop;

        -- 3. Fire if legal: consume (oldest first), then reset, then produce.
        if cmd_valid = '1' and blocked = (blocked'range => '0') then
          for i in ARCS'range loop
            arc := ARCS(i);
            if arc.dst = cmd_t and (arc.kind = ARC_IN or arc.kind = ARC_TIMED) then
              for w in 1 to arc.weight loop
                q(arc.src)(0 to TOK_MAX - 2) := q(arc.src)(1 to TOK_MAX - 1);
                c(arc.src) := c(arc.src) - 1;
              end loop;
            end if;
          end loop;
          for i in ARCS'range loop
            arc := ARCS(i);
            if arc.dst = cmd_t and arc.kind = ARC_RESET then
              c(arc.src) := 0;
            end if;
          end loop;
          for i in ARCS'range loop
            arc := ARCS(i);
            if arc.src = cmd_t and arc.kind = ARC_OUT then
              for w in 1 to arc.weight loop
                assert c(arc.dst) < PLACE_CAP(arc.dst)
                  report "place " & integer'image(arc.dst) & " exceeds its capacity"
                  severity failure;
                q(arc.dst)(c(arc.dst)) := 1;
                c(arc.dst) := c(arc.dst) + 1;
              end loop;
            end if;
          end loop;
          a(cmd_t) := 1;
        end if;

        t_age <= a;
        count <= c;
        tok <= q;
        verdict_valid <= cmd_valid;
        verdict_arcs <= blocked;
        if cmd_valid = '1' and blocked = (blocked'range => '0') then
          verdict_legal <= '1';
        else
          verdict_legal <= '0';
          if cmd_valid = '1' then
            n_viol <= n_viol + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
