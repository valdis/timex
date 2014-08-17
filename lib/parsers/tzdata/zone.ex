defmodule Timex.Parsers.Tzdata.Zone do
  @moduledoc """
  Defines the set of rules for a given timezone.
  """
  @derive Access
  defstruct name: "",
            rules: []

  defmodule Rule do
    @moduledoc """
    Represents the state of a timezone from the previous
    state's `until` value, right up to the datetime
    represented by the `until` value of the current state.
    """

              # The offset from UTC
    defstruct offset: {:+, {0, 0, 0}},
              # The rule used to determine whether this zone is observing DST
              # nil #=> No adjustment
              # 1:00 #=> Set the clocks ahead by this amount
              # Chicago #=> Check this rule to determine if we need to set the clocks ahead
              rule: nil,
              # The format for the zone abbrevation. If there are no variable parts, this format
              # will be a string value. If it is variable, then the format will be as follows:
              # {prefix, suffix}. When building the zone abbreviation, concatenate the prefix
              # and suffix around the variable character.
              format: "",
              # The date and time at which this zone will end. The time is
              # given in one of the following timezones:
              #   :local, :universal, :standard, :greenwich, :nautical
              until: {:local, {{0, 1, 1}, {0, 0, 0}}}
  end

end