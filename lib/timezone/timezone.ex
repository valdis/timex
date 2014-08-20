defmodule Timex.Timezone do
  @moduledoc """
  Contains all the logic around conversion, manipulation,
  and comparison of time zones.
  """
  alias Timex.Date
  alias Timex.DateTime
  alias Timex.TimezoneInfo
  alias Timex.Timezone.Local
  alias Timex.Timezone.Database

  @doc """
  Get's the current local timezone configuration.
  You can provide a reference date to get the local timezone
  for a specific date, but the operation will not be cached
  lik getting the local timezone for the current date
  """
  def local() do
    case Process.get(:local_timezone) do
      nil ->
        tz = Local.lookup() |> get
        Process.put(:local_timezone, tz)
        tz
      tz ->
        tz
    end
  end
  def local(date), do: Local.lookup(date) |> get

  defdelegate get(tz), to: Database

  @doc """
  Convert a date to the given timezone.
  """
  @spec convert(date :: DateTime.t, tz :: TimezoneInfo.t) :: DateTime.t
  def convert(date, tz) do
    # Calculate the difference between `date`'s timezone, and the provided timezone
    difference = diff(date, tz)
    # Offset the provided date's time by the difference
    Date.shift(date, mins: difference)
  end

  @doc """
  Determine what offset is required to convert a date into a target timezone
  """
  @spec diff(date :: DateTime.t, tz :: TimezoneInfo.t) :: integer
  def diff(%DateTime{:timezone => origin} = date, %TimezoneInfo{:offset => {dest_otype, dest_offset_raw}, is_dst?: dest_is_dst?} = dest) do
    %TimezoneInfo{:offset => {otype, offset_raw}, :is_dst? => is_dst?} = origin
    dest_offset = case dest_otype do
        :- -> (dest_offset_raw |> Time.to_mins) * -1
        :+ -> (dest_offset_raw |> Time.to_mins)
    end
    offset = case otype do
        :- -> (offset_raw |> Time.to_mins) * -1
        :+ -> (offset_raw |> Time.to_mins)
    end
    dest_offset - offset
  end

end