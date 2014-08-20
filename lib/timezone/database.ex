defmodule Timex.Timezone.Database do
  @moduledoc """
  This module provides access to the database of timezones.
  """

  alias Timex.Date
  alias Timex.DateTime
  alias Timex.Timezone
  alias Timex.TimezoneInfo
  alias Timex.Parsers.Tzdata.Leap
  alias Timex.Parsers.Tzdata.Rule
  alias Timex.Parsers.Tzdata.Zone
  alias Timex.Parsers.Tzdata.Link
  alias Timex.Parsers.Tzdata.Database, as: TzDatabase

  {_, olson_mappings}   = Path.join("priv", "standard_to_olson.exs") |> Code.eval_file
  {_, windows_mappings} = Path.join("priv", "olson_to_win.exs") |> Code.eval_file

  @database_file Path.join(["priv", "tzdata", "database.exs"]) |> Path.expand

  @doc """
  Persists the parsed Olson timezone database to disk.
  """
  def persist!(%TzDatabase{} = db) do
    if File.exists?(@database_file) do
      File.rm_rf!(@database_file)
    end
    db
    |> Inspect.Algebra.to_doc(%Inspect.Opts{pretty: false, limit: 99_000_000})
    |> Inspect.Algebra.format(99_000_000)
    |> do_persist!
  end

  defp do_persist!(db) do
    File.write!(@database_file, db)
  end

  # Compile database lookups
  if File.exists?(@database_file) do
    raw = File.read!(@database_file)
    {db, _} = Code.eval_string(raw, [], [file: __ENV__.file, line: __ENV__.line])
    # Define common operations for Zones
    db.zones
    |> Enum.map(fn zone -> {zone.name, zone.rules} end)
    |> Enum.each(fn {name, rules} ->
      Enum.each(rules, fn rule ->
        quote bind_quoted: [name: name, until: rule.until] do
          def equals?(%TimezoneInfo{name: unquote(name), until: unquote(until)},
                      %TimezoneInfo{name: unquote(name), until: unquote(until)}),
            do: true
        end
      end)
      def exists?(unquote(name)), do: true
      def link?(unquote(name)), do: false
    end)
    Enum.each db.links, fn %Link{to: to} ->
      def exists?(unquote(to)),
        do: true
      def link?(unquote(to)),
        do: true
    end
    def exists?(_),    do: false
    def equals?(_, _), do: false
    def link?(_),      do: false

    # Define lookups for leap seconds
    Enum.each db.leaps, fn %Leap{timestamp: {{y,m,d},{h,min,s}}=timestamp, type: type} = leap ->
      def is_leap?(%Date{year: dy, month: dm, day: dd, 
                         hour: dh, minute: dmin, second: ds,
                         timezone: %Timezone{name: name} = tz} = date) do
        leap_type = unquote(type)
        leap_time = unquote(timestamp)
        is_utc?   = equals?(name, "UTC")
        case {{{dy, dm, dd}, {dh, dmin, ds}}, is_utc?} do
          {^leap, true} when leap_type == :stationary -> 
            true
          {^leap, false} when leap_type == :rolling ->
            true
          _ ->
            false
        end
      end

      def next_leap?(%Date{year: dy, month: dm, day: dd, hour: dh, minute: dmin, second: ds})
        when ((dy * 100_000) + (dm * 10_000) + (dd * 1_000) + (dh * 100) + (dmin * 10) + (ds * 1)) <=
             unquote((y * 100_000) + (m * 10_000) + (d * 1_000) + (h * 100) + (min * 10) + (s * 100)) do
          leap
      end
    end
    def is_leap?(_),   do: false
    def next_leap?(_), do: :undefined

    # Enable users to query for a timezone info given a zone name,
    # or a zone name and a date
    Enum.each db.rules, fn (%Rule{name: name, start_year: syear, end_year: eyear, month: rmonth, at: {type, {at_h, at_m, at_s}}}=rule) ->
      # Detrmine boundaries for this rule
      {rule_start_date, rule_start_time, _type} = Rule.start_date?(rule)
      rule_start = :calendar.datetime_to_gregorian_seconds({rule_start_date, rule_start_time})
      rule_end = case Rule.end_date?(rule) do
        :never              -> :never
        {date, time, _type} -> :calendar.datetime_to_gregorian_seconds({date, time})
      end
      # Get zone rules
      #IO.inspect {name}
      zone = Enum.find db.zones, fn %Zone{name: zname} ->
        #IO.inspect {"zname", zname}
        zname == name
      end
      if zone != nil do
        zone_rule = Enum.find zone.rules, fn %Zone.Rule{until: until} = zrule ->
          zone_end = Rule.until_to_datetime(until) |> :calendar.datetime_to_gregorian_seconds
          (zone_end <= rule_start != true)
        end
        dst_rule             = zone_rule.rule
        rule_abbrev_variable = rule.abbreviation_variable
        rule_abbrev_format   = zone_rule.format
        rule_offset          = zone_rule.offset
        rule_until           = zone_rule.until

        
        {{zy,zm,zd},{zh,zmm,zs}} = Rule.until_to_datetime(zone_rule.until)
        hash = (zy*100_000)+(zm*10_000)+(zd*1_000)+(zh+100)+(zmm*10)+zs
        defp get_zone_for_date(unquote(name), {{y,m,d}, {h,mm,s}}=datetime) 
          when unquote(hash) < ((y*100_000)+(m*10_000)+(d*1_000)+(h+100)+(mm*10)+s)
          do
            is_dst? = case unquote(dst_rule) do
              nil     -> false
              {_,_,_} -> true
              altzone when is_binary(altzone) ->
                %TimezoneInfo{is_dst?: is_dst?} = get_zone_for_date(altzone, date)
                is_dst?
            end
            variable      = unquote(rule_abbrev_variable)
            abbrev_format = unquote(rule_abbrev_format)
            abbrev = case {abbrev_format, variable} do
              {pre, post, nil} ->
                pre <> post
              {pre, post, v} when is_binary(v) ->
                pre <> v <> post
              abbrev when is_binary(abbrev) ->
                abbrev
            end
            %TimezoneInfo{
              name: unquote(name),
              abbreviation: abbrev,
              offset: unquote(rule_offset),
              starts: unquote(rule_start_date),
              until: unquote(rule_until),
              is_dst?: is_dst?
            }
        end
      end
    end

    def get(timezone), do: get(timezone, :calendar.universal_time())
    def get(timezone, date) when timezone in [:utc, 0], do: get("UTC", date)
    def get(timezone, date) when timezone in ["A", "M", "N", "Y"] do
      case timezone do
        "A" -> get(-1,  date)
        "M" -> get(-12, date)
        "N" -> get(+1,  date)
        "Y" -> get(+12, date)
      end
    end
    def get(timezone, date) when timezone in [-12..12] do
      case timezone do
        0            -> get("UTC", date)
        n when n > 0 -> get("Etc/GMT+#{n}")
        n when n < 0 -> get("Etc/GMT#{n}")
      end
    end
    def get(<<?+, offset :: binary>>, date) do
      {num, _} = Integer.parse(offset)
      cond do
        num > 100 -> trunc(num/100) |> get
        true      -> get(num)
      end
    end
    def get(<<?-, offset :: binary>>, date) do
      {num, _} = Integer.parse(offset)
      cond do
        num > 100 -> get(trunc(num/100) * -1)
        true      -> get(num)
      end
    end
    def get(timezone, {{_,_,_},{_,_,_}} = datetime) do
      apply(__MODULE__, :get_zone_for_date, [timezone, datetime])
    end
    def get(timezone, %DateTime{year: y, month: m, day: d, hour: h, minute: mm, second: s}) do
      apply(__MODULE__, :get_zone_for_date, [timezone, {{y,m,d},{h,mm,s}}])
    end
  end

  @doc """
  Lookup the Olson time zone given it's standard name

  ## Example

    iex> Timex.Timezone.Database.to_olson("Azores Standard Time")
    "Atlantic/Azores"

  """
  Enum.each(olson_mappings, fn {key, value} ->
    quoted = quote do
      def to_olson(unquote(key)), do: unquote(value)
    end
    Module.eval_quoted __MODULE__, quoted, [], __ENV__
  end)
  def to_olson(_tz), do: nil

  @doc """
  Lookup the Windows time zone name given an Olson time zone name.

  ## Example

    iex> Timex.Timezone.Database.olson_to_win("Pacific/Noumea")
    Central Pacific Standard Time

  """
  Enum.each(windows_mappings, fn {key, value} ->
    quoted = quote do
      def olson_to_win(unquote(key)), do: unquote(value)
    end
    Module.eval_quoted __MODULE__, quoted, [], __ENV__
  end)
  def olson_to_win(_tz), do: nil
end