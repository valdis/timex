defmodule Timex.Parsers.Tzdata.Database do
  @moduledoc """
  A container for the Olson timezone database.
  """

  # Just %Rule{}, %Zone{}, %Leap{}, and %Link{} arrays
  @derive Access
  defstruct rules: [], zones: [], leaps: [], links: []
end