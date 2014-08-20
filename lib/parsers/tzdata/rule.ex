defmodule Timex.Parsers.Tzdata.Rule do
  @moduledoc """
  Defines the schema for rules governing changes between standard and daylight saving time
  """
  alias Timex.Parsers.Tzdata.Rule
  alias Timex.Parsers.Tzdata.Utils

  @derive Access
  defstruct name: "",
            start_year: :min,
            end_year: :max,
            type: nil,
            month: 1,
            on: :undef,
            at: {:local, {0, 0, 0}},
            # Wall clock offset from local standard time.
            # This is usually either zero for standard time or one hour for daylight saving time
            save: {:+, {0, 0, 0}},
            # The type of abbreviation letter to use for this rule.
            # this letter is used when building the timezone abbreviation
            # for times in this zone.
            #
            # Valid values are:
            #   :standard        #=> "S"
            #   :daylight_saving #=> "D"
            #   :daylight_saving #=> "DD"
            #   :war             #=> "W"
            #   :peace           #=> "P"
            #   :none
            abbreviation_variable: :none

  @doc """
  Given a Rule, get the datetime tuple + at_type (:local, :standard, :universal, etc.)
  representing the starting date for this rule.
  """
  def start_date(%Rule{start_year: start_year, month: month, on: on, at: {type, {_,_,_}=time}}) do
    year = case start_year do
      y when is_integer(y) -> y
      :min                 -> 0
    end
    get_rule_date(year, month, on, time, type)
  end

  @doc """
  Given a Rule, get either the datetime tuple + at_type (:local, :standard, :universal, etc.)
  representing the ending date for this rule, or :never, meaning the rule never ends.
  """
  def end_date(%Rule{end_year: end_year, month: month, on: on, at: {type, {_, _, _}=time}} = rule) do
    year = case end_year do
      y when is_integer(y) -> y
      :max                 -> :never
      :only                -> rule.start_year
    end
    get_rule_date(year, month, on, time, type)
  end

  defp get_rule_date(:infinity, _, _, _, _), do: :infinity
  defp get_rule_date(year, month, date_constraint, {_h, _m, _s}=time, type) do
    last_day = :calendar.last_day_of_the_month(year, month)
    date = case date_constraint do
      # Handle converting date constraints
      {_weekday, comp, _day} = constraint when is_atom(comp)->
        Utils.resolve_constraint(year, month, constraint)
      # Find the day of the last <weekday> of this month
      {:last, :monday} ->
        {year, month, Utils.last_instance_of(year, month, 1)}
      {:last, :tuesday} ->
        {year, month, Utils.last_instance_of(year, month, 2)}
      {:last, :wednesday} ->
        {year, month, Utils.last_instance_of(year, month, 3)}
      {:last, :thursday} ->
        {year, month, Utils.last_instance_of(year, month, 4)}
      {:last, :friday} ->
        {year, month, Utils.last_instance_of(year, month, 5)}
      {:last, :saturday} ->
        {year, month, Utils.last_instance_of(year, month, 6)}
      {:last, :sunday} ->
        {year, month, Utils.last_instance_of(year, month, 7)}
      # We were given the date, that's nice
      day when is_integer(day) ->
        {year, month, day}
    end
    # Make sure month boundaries are respected
    case date do
      {_, _, day_of_month} when day_of_month > last_day ->
        {type, {year, month, last_day}, time}
      {_, _, day_of_month} when day_of_month < 1 ->
        {type, {year, month, 1}, time}
      {_, _, _} ->
        {type, date, time}
    end
  end

end