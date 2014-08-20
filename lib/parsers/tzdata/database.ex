defmodule Timex.Parsers.Tzdata.Database do
  @moduledoc """
  A container for the Olson timezone database.
  """

  alias Timex.Parsers.Tzdata.Database
  alias Timex.Parsers.Tzdata.Zone
  alias Timex.Parsers.Tzdata.Rule
  alias Timex.Parsers.Tzdata.Utils
  alias Timex.TimezoneInfo

  # Just %TimezoneInfo, %Zone{}, %Rule{}, %Leap{}, and %Link{} lists
  @derive Access
  defstruct timezones: [], zones: [], rules: [], leaps: [], links: []

  def build!(%Zone{} = zones, %Rule{} = rules, %Leap{} = leaps, %Link{} = links) do
    db = %Database{zones: zones, rules: rules, leaps: leaps, links: links}
    # 3. For each world region, start by iterating over zones
    # 4. For each zone, fetch the rule which matches the zone's rule name and time boundaries
    # 5. Define a function to fetch that zone given a date
    timezones = Enum.flat_map zones, fn %Zone{name: zone_name, rules: zone_rules} ->
      Stream.transform zone_rules, :min, fn
        # If the last `until` was :infinity, we're done
        _, :infinity ->
          {:halt, :infinity}
        %Zone.Rule{offset: off, rule: dst_rule, format: abbr_fmt, until: until}, acc ->
          until = Utils.resolve_until(until)
          timezone = case dst_rule do
            # No DST rule for this zone
            nil            -> construct_timezone(zone_name, {:+, {0,0,0}}, off, abbr_fmt, acc, until)
            # We have been given the offset for DST, so this is a DST zone
            {_,_,_} = time -> construct_timezone(zone_name, {:+, time}, off, abbr_fmt, acc, until)
            # We have been given the name of a rule to check to verify DST, so we need to
            # lookup the rule, and first make sure the zone falls within the rule's start and end
            # dates ({type, date, time}), and secondly, determine from the rule whether this is
            # a dst date or not.
            rule_name      ->
              case Enum.find(rules, &locate_rule(&1, acc, until)) do
                %Rule{save: dst_offset, abbreviation_variable: var} ->
                  abbr = case abbr_fmt do
                    {pre, post}  -> pre <> var <> post
                    abbreviation -> abbreviation
                  end
                  is_dst? = rule.save != {:+, {0,0,0}}
                  construct_timezone(zone_name, rule.save, off, abbr, acc, until, is_dst?)
                nil ->
                  construct_timezone(zone_name, {:+, {0,0,0}}, off, abbr_fmt, acc, until, false)
              end
          end
          {[timezone], timezone.until}
      end
    end
  end

  ## TODO
  # Utils.compare_until
  # Utils.shift_offset

  ## RULE CHANGES (FINAL)
  # Given a Zone, for each period, check the Rule.
  # If the Rule is nil, there is no DST
  # If the Rule is a time, that is the adjustment to GMT offsest for DST
  # If the Rule is a name, then for the duration of that period, use the
  # transitions defined by the Rules of that name, for the period of time
  # specified by that Zone period.

  defp construct_timezone(name, _, offset, abbr, starts, until, false) do
    TimezoneInfo.new(name, abbr, offset, starts, until, is_dst?) do
  end

  defp construct_timezone(name, {h,m,s}, offset, abbr, starts, until, true) do
    dst_offset = Utils.shift_offset(offset, {:+, h, m, s})
    TimezoneInfo.new(name, abbr, dst_offset, starts, until, is_dst?) do
  end

  # Return false if the rule ends on or before from, or starts on or after until
  # Otherwise, return true, as this rule is valid for the given zone boundaries
  defp locate_rule(%Rule{} = rule, from, until) do
    rule_start = Rule.start_date(rule)
    rule_end   = Rule.end_date(rule)
    case {Utils.compare_until(rule_end, from), Utils.compare_until(rule_start, until)} do
      # Ends before zone start
      {:<, _}  -> false
      # Ends at zone start
      {:=, _}  -> false
      # Ends after zone start, but starts after zone end
      {:>, :>} -> false
      # Ends after zone start, but starts at zone end
      {:>, :=} -> false
      # Otherwise we're within a valid range
      _        -> true
    end
  end

end

