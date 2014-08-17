defmodule Timex.Parsers.Tzdata.Rule do
  @moduledoc """
  Defines the schema for rules governing changes between standard and daylight saving time
  """
  alias Timex.Parsers.Tzdata.Rule

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
  def start_date?(%Rule{start_year: start_year, month: month, on: on, at: {type, {_,_,_}=time}}) do
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
  def end_date?(%Rule{end_year: end_year, month: month, on: on, at: {type, {_, _, _}=time}} = rule) do
    year = case end_year do
      y when is_integer(y) -> y
      :max                 -> :never
      :only                -> rule.start_year
    end
    get_rule_date(year, month, on, time, type)
  end

  defp get_rule_date(:never, _, _, _, _), do: :never
  defp get_rule_date(year, month, date_constraint, {_h, _m, _s}=time, type) do
    last_day = :calendar.last_day_of_the_month(year, month)
    date = case date_constraint do
      # Handle converting date constraints
      {_constraint, _weekday, _day} = constraint->
        resolve_constraint(year, month, constraint)
      # Find the day of the last sunday of this month
      {:last, :sunday} ->
        {year, month, get_date_of_last_weekday(year, month, 7)}
      # Find the day of the last saturday of this month
      {:last, :saturday} ->
        {year, month, get_date_of_last_weekday(year, month, 6)}
      # We were given the date, that's nice
      day when is_integer(day) ->
        {year, month, day}
    end
    # Make sure month boundaries are respected
    case date do
      {_, _, day_of_month} when day_of_month > last_day ->
        {{year, month, last_day}, time, type}
      {_, _, day_of_month} when day_of_month < 1 ->
        {{year, month, 1}, time, type}
      {_, _, _} ->
        {date, time, type}
    end
  end

  defp resolve_constraint(year, month, {weekday, :>=, day}),
    do: get_date_of_next_weekday(year, month, day, weekday)
  defp resolve_constraint(year, month, {weekday, :<=, day}),
    do: get_date_of_previous_weekday(year, month, day, weekday)
  defp resolve_constraint(year, month, {weekday, :>, day}),
    do: get_date_of_next_weekday(year, month, day, weekday)
  defp resolve_constraint(year, month, {weekday, :<, day}),
    do: get_date_of_previous_weekday(year, month, day, weekday)
  defp resolve_constraint_day(_, _, {weekday, constraint, day}) do
    raise ArgumentError,
      message: "Cannot compute start date for Rule. Unknown constraint: #{weekday}#{constraint}#{day}"
  end
  defp resolve_constraint_day(_, _, constraint) do
    raise ArgumentError,
      message: "Cannot compute start date for Rule. Unknown constraint: #{Macro.to_string(constraint)}"
  end

  @days_per_week  7
  @first_of_month 1

  def get_date_of_first_weekday(year, month) do
    :calendar.day_of_the_week(year, month, 1)
  end
  def get_date_of_first_weekday(year, month, weekday) when weekday in 1..7 do
    first_weekday = :calendar.day_of_the_week(year, month, 1)
    @first_of_month + ((@days_per_week-(@days_per_week-first_weekday)-weekday)*-1)
  end

  def get_date_of_last_weekday(year, month) do
    last_day = :calendar.last_day_of_the_month(year, month)
    :calendar.day_of_the_week(year, month, last_day)
  end
  def get_date_of_last_weekday(year, month, weekday) when weekday in 1..7 do
    last_day     = :calendar.last_day_of_the_month(year, month)
    last_weekday = :calendar.day_of_the_week(year, month, last_day)
    last_day - (last_weekday+(@days_per_week*((last_day-weekday)/@days_per_week)))
  end

  def get_date_of_next_weekday(year, month, day, weekday)
    when weekday in 1..7,
    do: get_date_of_next_weekday(year, month, day, overflow: false)
  def get_date_of_next_weekday(year, month, day, weekday, overflow: overflow?)
    when weekday in 1..7
    do
      current_weekday = :calendar.day_of_the_week(year, month, day)
      last_instance   = get_date_of_last_weekday(year, month, weekday)
      cond do
        day == last_instance ->
          {year, month, last_instance}
        day > last_instance and div(month, 12) == 0 and overflow? ->
          {year, month+1, get_date_of_first_weekday(year, 1, weekday)}
        day > last_instance and div(month, 12) == 1 and overflow? ->
          {year+1, 1, get_date_of_first_weekday(year+1, 1, weekday)}
        day > last_instance and not overflow? ->
          {year, month, last_instance}
        day < last_instance and (last_instance-day) <= 7 ->
          {year, month, last_instance}
        day < last_instance and (last_instance-day) > 7 and (weekday - current_weekday == 0) ->
          {year, month, day + 7}
        day < last_instance and (last_instance-day) > 7 and (weekday - current_weekday > 0) ->
          {year, month, day + (weekday - current_weekday)}
        day < last_instance and (last_instance-day) > 7 and (weekday - current_weekday < 0) ->
          {year, month, (day - (current_weekday - weekday)) + 7}
        true ->
          raise ArgumentError,
            message: "Something is wrong with calculating date of next weekday. Report this bug!"
      end
  end

  def get_date_of_previous_weekday(year, month, day, weekday)
    when weekday in 1..7,
    do: get_date_of_previous_weekday(year, month, day, weekday, overflow: false)
  def get_date_of_previous_weekday(year, month, day, weekday, overflow: overflow?)
    when weekday in 1..7
    do
      current_weekday = :calendar.day_of_the_week(year, month, day)
      first_instance  = get_date_of_first_weekday(year, month, weekday)
      cond do
        day == first_instance ->
          {year, month, first_instance}
        day < first_instance and month > 1 and overflow? ->
          {year, month-1, get_date_of_last_weekday(year, month-1, weekday)}
        day < first_instance and month == 1 and overflow? ->
          {year-1, 12, get_date_of_last_weekday(year-1, 12, weekday)}
        day < first_instance and not overflow? ->
          {year, month, first_instance}
        day > first_instance and (day-first_instance) <= 7 ->
          {year, month, first_instance}
        day > first_instance and (day-first_instance) > 7 and (weekday - current_weekday == 0) ->
          {year, month, day + 7}
        day > first_instance and (day-first_instance) > 7 and (weekday - current_weekday > 0) ->
          {year, month, day + (weekday - current_weekday)}
        day > first_instance and (day-first_instance) > 7 and (weekday - current_weekday < 0) ->
          {year, month, (day - (current_weekday - weekday)) + 7}
        true ->
          raise ArgumentError,
            message: "Something is wrong with calculating date of previous weekday. Report this bug!"
      end
  end
end