defmodule Timex.Parsers.DateFormat.Tokenizers.Relative do
  @moduledoc """
  Responsible for tokenizing relative date/time formatting strings

  Rules cribbed from PHP: http://php.net/manual/en/datetime.formats.relative.php
  """
  use Timex.Parsers.DateFormat.Tokenizers.Tokenizer

  alias Timex.Parsers.DateFormat.ParserState, as: State
  alias Timex.Parsers.DateFormat.Directive,   as: Directive

  @dayname ~r/[mM]onday|[tT]uesday|[wW]ednesday|[tT]hursday|[fF]riday|[sS]aturday|[sS]unday/

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
end