defmodule Timex.Parsers.Tzdata.Parser do
  @moduledoc """
  Responsible for parsing tzdata files from the
  Olson timezone database.
  """

  alias Timex.Parsers.Tzdata.Rule
  alias Timex.Parsers.Tzdata.Zone
  alias Timex.Parsers.Tzdata.Leap
  alias Timex.Parsers.Tzdata.Link
  alias Timex.Parsers.Tzdata.Database

  @doc """
  Reads tzdata from a file on disk, and returns the parsed tzdata as
  {:ok, %TzDatabase{}}, or {:error, reason}.
  """
  @spec file(String.t) :: {:ok, term} | {:error, term}
  def file(path) do
    case File.exists?(path) do
      true ->
        path |> File.read! |> parse
      false ->
        {:error, "The provided path does not exist: #{path}"}
    end
  end

  def parse(nil),  do: {:error, "Cannot parse empty data!"}
  def parse(<<>>), do: {:error, "Cannot parse empty data!"}
  def parse(data) when is_binary(data) do
    case :tzdata.parse(data) do
      {:error, _} = error ->
        error
      [] ->
        {:error, "Parser found nothing to parse!"}
      results when is_list(results) ->
        do_parse(results, %Database{})
      wat ->
        {:error, "Unexpected parser return value: #{Macro.to_string(wat)}"}
    end
  end

  defp do_parse([], %Database{} = db), do: {:ok, db}
  defp do_parse([{:rule, name, {start, finish}, _type, month, on, at, save, letter}|rest], %Database{rules: rules} = db) do
    rule = %Rule{
      name:       name,
      start_year: start,
      end_year:   finish,
      month:      month,
      on:         on,
      at:         at,
      save:       save,
      abbreviation_variable: letter
    }
    db = %{db | :rules => [rule|rules]}
    do_parse(rest, db)
  end
  defp do_parse([{:zone, name, zone_changes}|rest], %Database{zones: zones} = db) do
    rules = Enum.map zone_changes, fn {offset, rule, format, until} ->
      %Zone.Rule{offset: offset, rule: rule, format: format, until: until || :infinity}
    end
    zone = %Zone{name: name, rules: rules}
    db   = %{db | :zones => [zone|zones]}
    do_parse(rest, db)
  end
  defp do_parse([{:leap, {{year, month, day}, {h, m, s}}=dt, correction, type}|rest], %Database{leaps: leaps} = db) do
    leap = %Leap{timestamp: dt, correction: correction, type: type}
    db   = %{db | :leaps => [leap|leaps]}
    do_parse(rest, db)
  end
  defp do_parse([{:link, from_zone, to_zone}|rest], %Database{links: links} = db) do
    link = %Link{from: from_zone, to: to_zone}
    db   = %{db | :links => [link|links]}
    do_parse(rest, db)
  end
  defp do_parse(wat), do: {:error, "Encountered unexpected data in parse result: #{Macro.to_string(wat)}"}
end