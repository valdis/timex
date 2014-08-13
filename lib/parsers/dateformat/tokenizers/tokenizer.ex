defmodule Timex.Parsers.DateFormat.Tokenizers.Tokenizer do
  @moduledoc """
  Defines the interface for tokenizers usable by Timex
  """
  use Behaviour

  alias Timex.Parsers.DateFormat.Directive

  defcallback tokenize(binary | nil) :: [%Directive{}] | {:error, term}

  defmacro __using__(_opts) do
    quote do
      @behaviour Timex.Parsers.DateFormat.Tokenizers.Tokenizer
    end
  end
end