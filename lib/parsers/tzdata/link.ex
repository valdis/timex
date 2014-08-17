defmodule Timex.Parsers.Tzdata.Link do
  @moduledoc """
  Defines a mapping between one rule and another.
  The link is equivalent to saying "this timezone is
  an alias for this other one, use it's rules".
  """

  # Both from and to are timezone names.
  @derive Access
  defstruct from: "", to: ""
end