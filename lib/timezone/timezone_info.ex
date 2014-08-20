defmodule Timex.TimezoneInfo do
  defstruct name: "",
            abbreviation: "",
            offset: 0,
            starts: :min,
            until: nil,
            is_dst?: false

  def new(name, abbr, {_, {_,_,_}} = offset, {type,{_,_,d},{_,_,_}} = starts, until, is_dst?)
    when is_binary(name)     and is_binary(abbr) and is_atom(type) and is_atom(until)
    and  is_boolean(is_dst?) and is_integer(d) do
      %TimezoneInfo{
        name: name, abbreviation: abbr,
        offset: offset,
        starts: starts, until: until,
        is_dst?: is_dst?
      }
  end
  def new(name, abbr, {_, {_,_,_}} = offset, {type,{_,_,d},{_,_,_}} = starts, {type2,{_,_,_},{_,_,_}} = until, is_dst?)
    when is_binary(name)     and is_binary(abbr) and is_atom(type) and is_atom(type2)
    and  is_boolean(is_dst?) and is_integer(d) do
      %TimezoneInfo{
        name: name, abbreviation: abbr,
        offset: offset,
        starts: starts, until: until,
        is_dst?: is_dst?
      }
end