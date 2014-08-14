defmodule Timex.Parsers.DateFormat.Tokenizers.Relative do
  @moduledoc """
  Responsible for tokenizing relative date/time formatting strings

  Rules cribbed from PHP: http://php.net/manual/en/datetime.formats.relative.php
  """
  use Timex.Parsers.DateFormat.Tokenizers.Tokenizer

  alias Timex.Parsers.DateFormat.ParserState, as: State
  alias Timex.Parsers.DateFormat.Directive,   as: Directive

  # Names of days of the month, rules for combining are that any ordinal less than 10 can be combined
  # (after) any ordinal above 19
  @ordinals       ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, 
                   "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12,
                   "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17,
                   "eighteenth": 18, "nineteenth": 19, "twentyth": 20, "twenty": 20, "thirty": 30]
  # Modifies the value
  @inc    &add(&1, 1)
  @dec    &add(&1, -1)
  @negate &multiply(&1, -1)
  @modifiers      ["next": @inc, "previous": @dec, "last": @inc, "this": @inc, "ago": @negate, "from": @add]
  # Units and their sizes
  @units          ["sec":         [unit: :second],
                   "second":      [unit: :second],
                   "min":         [unit: :minute],
                   "minute":      [unit: :minute], 
                   "hour":        [unit: :hour],
                   "day":         [unit: :day],
                   "week":        [unit: :day, size: 7],
                   "fortnight":   [unit: :day, size: 14],
                   "forthnight":  [unit: :day, size: 14],
                   "month":       [unit: :month],
                   "year":        [unit: :year],

  @value_phrases  %{"midnight"  => [hour: 24],
                    "yesterday" => [days: -1],
                    "today"     => [days: 0],
                    "few"       => [num: 2],
                    "couple"    => [num: 2],
                    ""
                    "now"       => [], # Take no action
                    "noon"      => [hour: 12],
                    "tomorrow"  => [hour: 0, days: +1],
                    "first day of" => [day: 1],
                    "last day of"  => [day: :last],
                    ""}

  @example_phrases [
    "a y ago",
    "a few ys ago", # few == two
    "a couple ys ago", # couple == two
    "x ys ago",
    "a y from now",
    "a few ys from now", # few == two
    "a couple ys from now" # couple == two
    "x ys from now",
    "at midnight yesterday",
    "at midnight on tuesday",
    "at midnight on the first of the month",
    "at midnight a few days ago",
    "a couple hours after midnight last night",
    "at nine last night",
    "at nine in the morning", # refers to today's morning
    "a few minutes past", # today, current hour + 2 minutes
    "a few minutes past three" # today, 3PM + 2 minutes
    "a few minutes past three thirty" # today, current hour + 17 minutes
    "a few minutes past 3:30"
    "half past", # today, current hour + 30 minutes
    "half past two" # today, 2PM + 30 minutes
    "nine tonight" # today at 21:00
    "nine this evening" # today at 21:00
  ]

  @doc """
  Takes a format string and extracts parsing directives for the parser.

  ## Example

    iex> Timex.Parsers.Tokenizers.Strftime.tokenize("%Y-%0m-%d")
    [%Directive{token: :year4, ...}, %Directive{token: :month, pad: 1, ...}, ...]
  """
  def tokenize(s) when s in [nil, ""], do: {:error, "Format string cannot be nil or empty!"}
  def tokenize(s) when is_list(s), do: tokenize("#{s}")
  def tokenize(s) do
    s
  end

  defp add(x, y),      do: x + y
  defp multiply(x, y), do: x * y
end