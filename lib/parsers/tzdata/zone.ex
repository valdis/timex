defmodule Timex.Parsers.Tzdata.Zone do
  @moduledoc """
  Defines the set of rules for a given timezone.
  """
  alias Timex.Parsers.Tzdata.Utils

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
              #   :local, :universal, :standard, :greenwich, :zulu
              until: {:local, {{0, 1, 1}, {0, 0, 0}}}

    def until_to_datetime(:infinity), do: :infinity
    def until_to_datetime({_type, {{y,m,{_,_,_}=constraint},{_,_,_}=time}}),
      do: {Utils.resolve_constraint(y, m, constraint), time}
    def until_to_datetime({_type, {{_,_,_},{_,_,_}} = datetime}),
      do: datetime
    end

  end
end