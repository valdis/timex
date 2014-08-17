defmodule Timex.Parsers.Tzdata.Leap do
  @moduledoc """
  Defines when leap seconds occur at specific points in time.
  """
  @derive Access
  defstruct timestamp: {{0, 1, 1}, {0, 0, 0}},
            # Whether to add or subtract the leap second
            # Can be :- or :+
            correction: :+,
            # Whether the timestamp is given in local time (:rolling)
            # or in UTC (:stationary).
            type: :rolling # or :stationary
end