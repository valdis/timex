defmodule Timex.Parsers.Tzdata.Utils do
  @moduledoc false

  alias Timex.Date

  @type year       Date.year
  @type month      Date.month
  @type day        Date.day
  @type weekday    Date.weekday
  @type date       Date.date
  @type time       Date.time
  @type datetime   Date.datetime
  @type comparator (:>= | :<= | :> | :<)
  @type until_type (:local | :universal | :standard | :greenwich | :zulu)
  @type constraint ({weekday, comparator, day} | day)
  @type resolved_until {until_type, date, time}

  @days_per_week  7
  @first_of_month 1

  @doc """
  Resolves a DST day change constraint. e.g. "Sun>=8"
  This reads as: the first Sunday which is on or after the 8th.

  Given a year, month, and constraint, calculate the full date on
  which this day will fall.
  """
  @spec resolve_constraint(year, month, {String.t, comparator, weekday}) :: datetime | no_return
  def resolve_constraint(year, month, {weekday, :>=, day}),
    do: next_instance_of(year, month, day, weekday)
  def resolve_constraint(year, month, {weekday, :<=, day}),
    do: previous_instance_of(year, month, day, weekday)
  def resolve_constraint(year, month, {weekday, :>, day}),
    do: next_instance_of(year, month, day, weekday)
  def resolve_constraint(year, month, {weekday, :<, day}),
    do: previous_instance_of(year, month, day, weekday)
  def resolve_constraint_day(_, _, {weekday, constraint, day}) do
    raise ArgumentError,
      message: "Cannot resolve constraint. Unknown format: #{weekday}#{constraint}#{day}"
  end
  def resolve_constraint_day(_, _, constraint) do
    raise ArgumentError,
      message: "Cannot resolve constraint. Unknown format: #{Macro.to_string(constraint)}"
  end

  @doc """
  Given a specification for how long a zone is active until it ends, e.g.
  {:local, {2014, 10, {7, :>=, 8}}, {23, 59, 59}}, resolve the day constraint
  to an actual date, such that the resul is of the form: {type, {y,m,d}, {h,mm,s}}
  """
  @spec resolve_until({until_type, {year, month, constraint}, time}) :: resolved_until
  def resolve_until({type, {year, month, {_,_,_} = constraint}, {_,_,_} = time}) when is_atom(type) do
    {type, {year, month, resolve_constraint(year, month, constraint)}, time}
  end
  def resolve_until({type, {_,_,_}, {_,_,_}} = resolved) when is_atom(type) do
    resolved
  end

  @doc """
  Given a year and month, get the weekday of the first day of the month.
  Weekdays range from 1 (Monday) to 7 (Sunday)
  """
  @spec first_weekday(year, month) :: weekday
  def first_weekday(year, month) do
    :calendar.day_of_the_week(year, month, 1)
  end

  @doc """
  Given a year and month, get the weekday of the last day of the month.
  Weekdays range from 1 (Monday) to 7 (Sunday)
  """
  def get_date_of_last_weekday(year, month) do
    last_day = :calendar.last_day_of_the_month(year, month)
    :calendar.day_of_the_week(year, month, last_day)
  end

  @doc """
  Given a year, month, and weekday, get the day on which the first instance
  of that weekday occurs.
  """
  @spec first_instance_of(year, month, weekday) :: day
  def first_instance_of(year, month, weekday) when weekday in 1..7 do
    first_weekday = :calendar.day_of_the_week(year, month, 1)
    @first_of_month + ((@days_per_week-(@days_per_week-first_weekday)-weekday)*-1)
  end

  @doc """
  Given a year, month, and weekday, get the day on which the last instance
  of that weekday occurs.
  """
  @spec last_instance_of(year, month, weekday) :: day
  def last_instance_of(year, month, weekday) when weekday in 1..7 do
    last_day     = :calendar.last_day_of_the_month(year, month)
    last_weekday = :calendar.day_of_the_week(year, month, last_day)
    trunc(last_day - (last_weekday+(@days_per_week*((last_day-weekday)/@days_per_week))))
  end

  @doc """
  Given a year, month, day and weekday, get the date on which the next instance
  of that weekday occurs (looking forward in time).

  If `overflow: true` is given, then if the next occurance of that weekday is in
  the next month, then the date will be rolled over +1 month. If the
  month provided is December, then the year will be rolled over as well.

  Defaults to `overflow: false`. When false, if the last instance of the weekday in
  that month is on or before the provided date, that date will be returned instead.
  """
  @spec next_instance_of(year, month, day, weekday, nil | [{:overflow, boolean}])
  def next_instance_of(year, month, day, weekday, options \\ [overflow: false])

  def next_instance_of(year, month, day, weekday, nil)
    when weekday in 1..7,
    do: next_instance_of(year, month, day, weekday, overflow: false)
  def next_instance_of(year, month, day, weekday, overflow: overflow?)
    when weekday in 1..7
    do
      current_weekday = :calendar.day_of_the_week(year, month, day)
      last_instance   = last_instance_of(year, month, weekday)
      cond do
        day == last_instance ->
          {year, month, last_instance}
        day > last_instance and div(month, 12) == 0 and overflow? ->
          {year, month+1, first_instance_of(year, 1, weekday)}
        day > last_instance and div(month, 12) == 1 and overflow? ->
          {year+1, 1, first_instance_of(year+1, 1, weekday)}
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

  @doc """
  Given a year, month, day and weekday, get the date on which the most recent instance
  of that weekday occurs (looking backward in time).

  If `overflow: true` is given, then if the previous occurance of that weekday is in
  the previous month, then the date will be rolled back 1 month. If the
  month provided is January, then the year will be rolled back as well.

  Defaults to `overflow: false`. When false, if the first instance of the weekday in
  that month is on or after the provided date, that date will be returned instead.
  """
  @spec previous_instance_of(year, month, day, weekday, nil | [{:overflow, boolean}])
  def previous_instance_of(year, month, day, weekday, options \\ [overflow: false])

  def previous_instance_of(year, month, day, weekday)
    when weekday in 1..7,
    do: previous_instance_of(year, month, day, weekday, overflow: false)
  def previous_instance_of(year, month, day, weekday, overflow: overflow?)
    when weekday in 1..7
    do
      current_weekday = :calendar.day_of_the_week(year, month, day)
      first_instance  = first_instance_of(year, month, weekday)
      cond do
        day == first_instance ->
          {year, month, first_instance}
        day < first_instance and month > 1 and overflow? ->
          {year, month-1, last_instance_of(year, month-1, weekday)}
        day < first_instance and month == 1 and overflow? ->
          {year-1, 12, last_instance_of(year-1, 12, weekday)}
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