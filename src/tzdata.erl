-module(tzdata).
-export([parse/1,file/1]).
-define(p_anything,true).
-define(p_charclass,true).
-define(p_choose,true).
-define(p_not,true).
-define(p_one_or_more,true).
-define(p_optional,true).
-define(p_scan,true).
-define(p_seq,true).
-define(p_string,true).
-define(p_zero_or_more,true).



%% -------------------------------------------------------------------
%%
%% tzdata: Parser for the Olson timezone database.
%%
%% Copyright (c) 2014 Paul Schoenfelder.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-define(line, true).
-define(FMT(F,A), lists:flatten(io_lib:format(F,A))).

parse_until([Year, _, Month, _, WeekDay, Comp, Number, _, Time, Type]) ->
    { Type, { {Year, Month, { WeekDay, Comp, Number }}, Time }};
parse_until([Year, _, Month, _, WeekDay, Comp, Number, _, Time]) ->
    { local, { {Year, Month, { WeekDay, Comp, Number }}, Time }};
parse_until([Year, _, Month, _, Day, Time, Type]) when is_atom(Type)->
    { Type, { {Year, Month, Day }, Time }};
parse_until([Year, _, Month, _, WeekDay, Comp, Number]) when is_atom(Comp) ->
    { local, { {Year, Month, { WeekDay, Comp, Number }}, {0,0,0} }};
parse_until([Year, _, Month, _, Day, _, Time]) ->
    Type = [lists:last(Time)],
    case string:to_integer(Type) of
        { error, _ } ->
            parse_until([Year, Month, Day, lists:reverse(tl(lists:reverse(Time))), Type]);
        _Default ->
            parse_until([Year, Month, Day, Time, ""])
    end;
parse_until([Year, _, Month, _, Day]) ->
    { local, { {Year, Month, Day}, {0,0,0} }};
parse_until([Year, _, Month]) ->
    { local, { {Year, Month, 1}, {0,0,0} }};
parse_until(Year) ->
    { local, { {Year,1,1}, {0,0,0} }}.

parse_until() ->
    infinity.

%% @doc Only let through lines that are not comments or whitespace.
is_valid(ignore)  -> false;
is_valid(_)       -> true.

strip_comments(ZoneChanges) ->
    strip_comments(ZoneChanges, []).

strip_comments([], Acc) ->
    Acc;
strip_comments([[[comment|_]|_] | Rest], Acc) ->
    strip_comments(Rest, Acc);
strip_comments([H|Rest], Acc) ->
    strip_comments(Rest, [H|Acc]).


-spec file(file:name()) -> any().
file(Filename) -> case file:read_file(Filename) of {ok,Bin} -> parse(Bin); Err -> Err end.

-spec parse(binary() | list()) -> any().
parse(List) when is_list(List) -> parse(list_to_binary(List));
parse(Input) when is_binary(Input) ->
  _ = setup_memo(),
  Result = case 'tzdata'(Input,{{line,1},{column,1}}) of
             {AST, <<>>, _Index} -> AST;
             Any -> Any
           end,
  release_memo(), Result.

-spec 'tzdata'(input(), index()) -> parse_result().
'tzdata'(Input, Index) ->
  p(Input, Index, 'tzdata', fun(I,D) -> (p_zero_or_more(fun 'line'/2))(I,D) end, fun(Node, _Idx) ->
    [ L || L <- Node, is_valid(L) ]
 end).

-spec 'line'(input(), index()) -> parse_result().
'line'(Input, Index) ->
  p(Input, Index, 'line', fun(I,D) -> (p_choose([p_seq([p_choose([fun 'rule'/2, fun 'link'/2, fun 'zone'/2, fun 'leap'/2, fun 'comment'/2, p_zero_or_more(fun 'ws'/2)]), p_choose([fun 'comment'/2, p_zero_or_more(fun 'ws'/2)]), p_choose([fun 'crlf'/2, fun 'eof'/2])]), fun 'crlf'/2]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        [{rule,_,_,_,_,_,_,_,_}=Rule, _, _] -> Rule;
        [{link,_,_}=Link, _, _]             -> Link;
        [{zone,_,_}=Zone, _, _]             -> Zone;
        [{leap,_,_,_}=Leap, _, _]           -> Leap;
        [ _Line, _EOL ]                     -> ignore;
        _Line                               -> ignore
    end
 end).

-spec 'rule'(input(), index()) -> parse_result().
'rule'(Input, Index) ->
  p(Input, Index, 'rule', fun(I,D) -> (p_seq([p_not(p_choose([p_seq([p_zero_or_more(fun 'ws'/2), fun 'crlf'/2]), fun 'comment'/2])), p_string(<<"Rule">>), p_one_or_more(fun 'ws'/2), fun 'word'/2, p_one_or_more(fun 'ws'/2), fun 'year_range'/2, p_one_or_more(fun 'ws'/2), fun 'type'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'on'/2, p_one_or_more(fun 'ws'/2), fun 'at'/2, p_one_or_more(fun 'ws'/2), fun 'save'/2, p_one_or_more(fun 'ws'/2), fun 'letter'/2]))(I,D) end, fun(Node, _Idx) ->
    [_, _, _, Name, _, YearRange, _, Type, _, Month, _, On, _, At, _, Save, _, Letter] = Node,
    {rule, Name, YearRange, Type, Month, On, At, Save, Letter}
 end).

-spec 'link'(input(), index()) -> parse_result().
'link'(Input, Index) ->
  p(Input, Index, 'link', fun(I,D) -> (p_seq([p_not(p_choose([p_seq([p_zero_or_more(fun 'ws'/2), fun 'crlf'/2]), fun 'comment'/2])), p_string(<<"Link">>), p_one_or_more(fun 'ws'/2), fun 'word'/2, p_one_or_more(fun 'ws'/2), fun 'word'/2]))(I,D) end, fun(Node, _Idx) ->
    [_, _, _, FromZone, _, ToZone] = Node,
    {link, FromZone, ToZone} 
 end).

-spec 'zone'(input(), index()) -> parse_result().
'zone'(Input, Index) ->
  p(Input, Index, 'zone', fun(I,D) -> (p_seq([p_not(p_choose([p_seq([p_zero_or_more(fun 'ws'/2), fun 'crlf'/2]), fun 'comment'/2])), p_string(<<"Zone">>), p_one_or_more(fun 'ws'/2), fun 'word'/2, p_one_or_more(fun 'ws'/2), fun 'zone_changes'/2]))(I,D) end, fun(Node, _Idx) ->
    [_, _, _, Name, _, ZoneChanges] = Node,
    {zone, Name, ZoneChanges}
 end).

-spec 'leap'(input(), index()) -> parse_result().
'leap'(Input, Index) ->
  p(Input, Index, 'leap', fun(I,D) -> (p_seq([p_not(p_choose([p_seq([p_zero_or_more(fun 'ws'/2), fun 'crlf'/2]), fun 'comment'/2])), p_string(<<"Leap">>), p_one_or_more(fun 'ws'/2), fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'day'/2, p_one_or_more(fun 'ws'/2), fun 'time'/2, p_one_or_more(fun 'ws'/2), fun 'correction'/2, p_one_or_more(fun 'ws'/2), fun 'leap_type'/2]))(I,D) end, fun(Node, _Idx) ->
    [_, _, _, Year, _, Month, _, Day, _, Time, _, Corr, _, LeapType] = Node,
    {leap, {{Year, Month, Day}, Time}, Corr, LeapType}
 end).

-spec 'zone_changes'(input(), index()) -> parse_result().
'zone_changes'(Input, Index) ->
  p(Input, Index, 'zone_changes', fun(I,D) -> (p_choose([p_seq([fun 'offset'/2, p_one_or_more(fun 'ws'/2), fun 'rules'/2, p_one_or_more(fun 'ws'/2), fun 'format'/2, p_one_or_more(fun 'ws'/2), fun 'until'/2, p_choose([fun 'comment'/2, p_zero_or_more(fun 'ws'/2)]), fun 'crlf'/2, p_zero_or_more(fun 'ws'/2), p_choose([p_seq([p_one_or_more(p_seq([fun 'comment'/2, p_zero_or_more(fun 'ws'/2), fun 'crlf'/2, p_zero_or_more(fun 'ws'/2)])), fun 'zone_changes'/2]), fun 'zone_changes'/2])]), p_seq([fun 'offset'/2, p_one_or_more(fun 'ws'/2), fun 'rules'/2, p_one_or_more(fun 'ws'/2), fun 'format'/2, p_choose([fun 'comment'/2, p_zero_or_more(fun 'ws'/2)])])]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        [Offset, _, Rules, _, Format, _] ->
            [{Offset, Rules, Format, parse_until()}];
        [Offset, _, Rules, _, Format, _, Until, _, _, _, [[[comment|_]|_], ZoneChanges]] ->
            CommentsStripped = strip_comments(ZoneChanges),
            [{Offset, Rules, Format, Until} | CommentsStripped];
        [Offset, _, Rules, _, Format, _, Until, _, _, _, ZoneChanges] ->
            CommentsStripped = strip_comments(ZoneChanges),
            [{Offset, Rules, Format, Until} | CommentsStripped]
    end
 end).

-spec 'on'(input(), index()) -> parse_result().
'on'(Input, Index) ->
  p(Input, Index, 'on', fun(I,D) -> (p_choose([p_seq([fun 'weekday'/2, fun 'comparison'/2, fun 'number'/2]), fun 'day'/2]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        [Weekday, Comp, Num] -> {Weekday, Comp, Num};
        {last, _}            -> Node;
        _Default             -> Node
    end
 end).

-spec 'until'(input(), index()) -> parse_result().
'until'(Input, Index) ->
  p(Input, Index, 'until', fun(I,D) -> (p_zero_or_more(p_choose([p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'weekday'/2, fun 'comparison'/2, fun 'number'/2, p_one_or_more(fun 'ws'/2), fun 'time'/2, fun 'at_type'/2]), p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'weekday'/2, fun 'comparison'/2, fun 'number'/2, p_one_or_more(fun 'ws'/2), fun 'time'/2]), p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'day'/2, p_one_or_more(fun 'ws'/2), fun 'time'/2, fun 'at_type'/2]), p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'day'/2, p_one_or_more(fun 'ws'/2), fun 'time'/2]), p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'weekday'/2, fun 'comparison'/2, fun 'number'/2]), p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2, p_one_or_more(fun 'ws'/2), fun 'day'/2]), p_seq([fun 'year'/2, p_one_or_more(fun 'ws'/2), fun 'month'/2]), fun 'year'/2])))(I,D) end, fun(Node, _Idx) ->
    case Node of
        []      -> parse_until();
        [Until] -> parse_until(Until)
    end
 end).

-spec 'rules'(input(), index()) -> parse_result().
'rules'(Input, Index) ->
  p(Input, Index, 'rules', fun(I,D) -> (p_choose([p_string(<<"-">>), fun 'time'/2, fun 'word'/2]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        <<$->>    -> nil;
        {_, _, _} -> Node;
        _Default  -> Node
    end
 end).

-spec 'format'(input(), index()) -> parse_result().
'format'(Input, Index) ->
  p(Input, Index, 'format', fun(I,D) -> (p_choose([p_string(<<"zzz">>), fun 'word'/2]))(I,D) end, fun(Node, _Idx) ->
    Format = binary_to_list(Node),
    case Format of
        "zzz" ->
            nil;
        _Other ->
            case string:tokens(Format, "%s") of
                []              -> { <<>>, <<>> };
                [Name]          -> list_to_binary(Name);
                [Before, After] -> { list_to_binary(Before), list_to_binary(After) }
            end
    end
 end).

-spec 'at'(input(), index()) -> parse_result().
'at'(Input, Index) ->
  p(Input, Index, 'at', fun(I,D) -> (p_choose([p_seq([fun 'time'/2, fun 'at_type'/2]), p_string(<<"0">>), fun 'word'/2]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        <<$0>> ->
            { local, { 0, 0, 0 } };
        [{Hour, Minute, Second}, AtType] ->
            {AtType, {Hour, Minute, Second}};
        Anything ->
            list_to_binary(Anything)
    end
 end).

-spec 'at_type'(input(), index()) -> parse_result().
'at_type'(Input, Index) ->
  p(Input, Index, 'at_type', fun(I,D) -> (p_zero_or_more(p_choose([p_string(<<"w">>), p_string(<<"u">>), p_string(<<"s">>), p_string(<<"g">>), p_string(<<"z">>)])))(I,D) end, fun(Node, _Idx) ->
    case Node of
        [] -> local;
        [AtType] ->
            case binary_to_list(AtType) of
                ""  -> local;
                "w" -> local;
                "u" -> universal;
                "s" -> standard;
                "g" -> greenwich;
                "z" -> zulu
            end
    end
 end).

-spec 'save'(input(), index()) -> parse_result().
'save'(Input, Index) ->
  p(Input, Index, 'save', fun(I,D) -> (fun 'offset'/2)(I,D) end, fun(Node, Idx) ->transform('save', Node, Idx) end).

-spec 'offset'(input(), index()) -> parse_result().
'offset'(Input, Index) ->
  p(Input, Index, 'offset', fun(I,D) -> (p_choose([p_seq([p_optional(p_string(<<"-">>)), fun 'time'/2]), p_string(<<"0">>), p_string(<<"1">>)]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        [<<$->>, {Hour, Minutes, Seconds}] -> { '-', { Hour, Minutes, Seconds } };
        [_, {Hour, Minutes, Seconds}]      -> { '+', { Hour, Minutes, Seconds } };
        <<$0>>                             -> { '+', { 0, 0, 0 } };
        <<$1>>                             -> { '+', { 1, 0, 0 } }
    end
 end).

-spec 'letter'(input(), index()) -> parse_result().
'letter'(Input, Index) ->
  p(Input, Index, 'letter', fun(I,D) -> (p_choose([p_string(<<"S">>), p_string(<<"DD">>), p_string(<<"D">>), p_string(<<"W">>), p_string(<<"P">>), p_string(<<"-">>), fun 'word'/2]))(I,D) end, fun(Node, _Idx) ->
    case binary_to_list(Node) of
        "S"  -> standard;
        "D"  -> daylight_saving;
        "DD" -> daylight_saving;
        "W"  -> war;
        "P"  -> peace;
        "-"  -> none;
        _L   -> none
    end
 end).

-spec 'year_range'(input(), index()) -> parse_result().
'year_range'(Input, Index) ->
  p(Input, Index, 'year_range', fun(I,D) -> (p_seq([p_choose([p_string(<<"min">>), fun 'year'/2]), p_one_or_more(fun 'ws'/2), p_choose([p_string(<<"only">>), p_string(<<"max">>), fun 'year'/2])]))(I,D) end, fun(Node, _Idx) ->
    [From, _, To] = Node,
    case {From, To} of
        {_, <<"only">>} ->
            { From, only };
        {_, <<"max">>} ->
            { From, max };
        {<<"min">>, _} ->
            { min, To };
        {_, _} ->
            { From, To }
    end
 end).

-spec 'year'(input(), index()) -> parse_result().
'year'(Input, Index) ->
  p(Input, Index, 'year', fun(I,D) -> (p_one_or_more(fun 'digit'/2))(I,D) end, fun(Node, _Idx) ->
    binary_to_integer(iolist_to_binary(Node))
 end).

-spec 'month'(input(), index()) -> parse_result().
'month'(Input, Index) ->
  p(Input, Index, 'month', fun(I,D) -> (p_choose([p_string(<<"Jan">>), p_string(<<"Feb">>), p_string(<<"Mar">>), p_string(<<"Apr">>), p_string(<<"May">>), p_string(<<"Jun">>), p_string(<<"Jul">>), p_string(<<"Aug">>), p_string(<<"Sep">>), p_string(<<"Oct">>), p_string(<<"Nov">>), p_string(<<"Dec">>)]))(I,D) end, fun(Node, _Idx) ->
    case binary_to_list(Node) of
        "Jan" -> 1;
        "Feb" -> 2;
        "Mar" -> 3;
        "Apr" -> 4;
        "May" -> 5;
        "Jun" -> 6;
        "Jul" -> 7;
        "Aug" -> 8;
        "Sep" -> 9;
        "Oct" -> 10;
        "Nov" -> 11;
        "Dec" -> 12
    end
 end).

-spec 'weekday'(input(), index()) -> parse_result().
'weekday'(Input, Index) ->
  p(Input, Index, 'weekday', fun(I,D) -> (p_choose([p_string(<<"Mon">>), p_string(<<"Tue">>), p_string(<<"Wed">>), p_string(<<"Thu">>), p_string(<<"Fri">>), p_string(<<"Sat">>), p_string(<<"Sun">>)]))(I,D) end, fun(Node, _Idx) ->
    case binary_to_list(Node) of
        "Mon" -> 1;
        "Tue" -> 2;
        "Wed" -> 3;
        "Thu" -> 4;
        "Fri" -> 5;
        "Sat" -> 6;
        "Sun" -> 7
    end
 end).

-spec 'day'(input(), index()) -> parse_result().
'day'(Input, Index) ->
  p(Input, Index, 'day', fun(I,D) -> (fun 'word'/2)(I,D) end, fun(Node, _Idx) ->
    Day = binary_to_list(Node),
    case Day of
        "lastMon" -> { last, monday };
        "lastTue" -> { last, tuesday };
        "lastWed" -> { last, wednesday };
        "lastThu" -> { last, thursday };
        "lastFri" -> { last, friday };
        "lastSat" -> { last, saturday };
        "lastSun" -> { last, sunday };
        _Default ->
            case string:to_integer(Day) of
                { error, _ } ->
                    list_to_binary(Day);
                { Result, _ } ->
                    Result
            end
    end
 end).

-spec 'time'(input(), index()) -> parse_result().
'time'(Input, Index) ->
  p(Input, Index, 'time', fun(I,D) -> (p_choose([p_seq([fun 'hour'/2, p_string(<<":">>), fun 'minute'/2, p_string(<<":">>), fun 'second'/2]), p_seq([fun 'hour'/2, p_string(<<":">>), fun 'minute'/2]), fun 'hour'/2]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        [Hour, _, Min, _, Sec] ->
            {Hour, Min, Sec};
        [Hour, _, Min] ->
            {Hour, Min, 0};
        Hour ->
            {Hour, 0, 0}
    end
 end).

-spec 'correction'(input(), index()) -> parse_result().
'correction'(Input, Index) ->
  p(Input, Index, 'correction', fun(I,D) -> (p_choose([p_string(<<"+">>), p_string(<<"-">>)]))(I,D) end, fun(Node, Idx) ->transform('correction', Node, Idx) end).

-spec 'comparison'(input(), index()) -> parse_result().
'comparison'(Input, Index) ->
  p(Input, Index, 'comparison', fun(I,D) -> (p_choose([p_string(<<">=">>), p_string(<<"<=">>), p_string(<<">">>), p_string(<<"<">>)]))(I,D) end, fun(Node, _Idx) ->
    list_to_atom(binary_to_list(Node))
 end).

-spec 'leap_type'(input(), index()) -> parse_result().
'leap_type'(Input, Index) ->
  p(Input, Index, 'leap_type', fun(I,D) -> (p_choose([p_string(<<"S">>), p_string(<<"R">>)]))(I,D) end, fun(Node, _Idx) ->
    case Node of
        <<$S>> -> stationary;
        <<$R>> -> rolling
    end
 end).

-spec 'type'(input(), index()) -> parse_result().
'type'(Input, Index) ->
  p(Input, Index, 'type', fun(I,D) -> (p_string(<<"-">>))(I,D) end, fun(_Node, _Idx) ->
    nil
 end).

-spec 'number'(input(), index()) -> parse_result().
'number'(Input, Index) ->
  p(Input, Index, 'number', fun(I,D) -> (p_one_or_more(fun 'digit'/2))(I,D) end, fun(Node, _Idx) ->
    binary_to_integer(iolist_to_binary(Node))
 end).

-spec 'hour'(input(), index()) -> parse_result().
'hour'(Input, Index) ->
  p(Input, Index, 'hour', fun(I,D) -> (fun 'double_digit'/2)(I,D) end, fun(Node, Idx) ->transform('hour', Node, Idx) end).

-spec 'minute'(input(), index()) -> parse_result().
'minute'(Input, Index) ->
  p(Input, Index, 'minute', fun(I,D) -> (fun 'double_digit'/2)(I,D) end, fun(Node, Idx) ->transform('minute', Node, Idx) end).

-spec 'second'(input(), index()) -> parse_result().
'second'(Input, Index) ->
  p(Input, Index, 'second', fun(I,D) -> (fun 'double_digit'/2)(I,D) end, fun(Node, Idx) ->transform('second', Node, Idx) end).

-spec 'double_digit'(input(), index()) -> parse_result().
'double_digit'(Input, Index) ->
  p(Input, Index, 'double_digit', fun(I,D) -> (p_choose([p_seq([fun 'digit'/2, fun 'digit'/2]), fun 'digit'/2]))(I,D) end, fun(Node, _Idx) ->
    case Node of 
        [_Tens, _Ones] -> list_to_integer(Node);
        Ones           -> list_to_integer([Ones])
    end
 end).

-spec 'digit'(input(), index()) -> parse_result().
'digit'(Input, Index) ->
  p(Input, Index, 'digit', fun(I,D) -> (p_charclass(<<"[0-9]">>))(I,D) end, fun(Node, _Idx) ->
    [Digit] = binary_to_list(Node),
    Digit
 end).

-spec 'word'(input(), index()) -> parse_result().
'word'(Input, Index) ->
  p(Input, Index, 'word', fun(I,D) -> (p_one_or_more(p_charclass(<<"[-+_:a-zA-Z0-9%\/]">>)))(I,D) end, fun(Node, _Idx) ->
    iolist_to_binary(Node)
 end).

-spec 'comment'(input(), index()) -> parse_result().
'comment'(Input, Index) ->
  p(Input, Index, 'comment', fun(I,D) -> (p_seq([p_zero_or_more(fun 'ws'/2), p_string(<<"#">>), p_zero_or_more(p_seq([p_not(fun 'crlf'/2), p_anything()]))]))(I,D) end, fun(_Node, _Idx) ->comment end).

-spec 'crlf'(input(), index()) -> parse_result().
'crlf'(Input, Index) ->
  p(Input, Index, 'crlf', fun(I,D) -> (p_seq([p_optional(p_string(<<"\r">>)), p_string(<<"\n">>)]))(I,D) end, fun(_Node, _Idx) ->ws end).

-spec 'eof'(input(), index()) -> parse_result().
'eof'(Input, Index) ->
  p(Input, Index, 'eof', fun(I,D) -> (p_not(p_anything()))(I,D) end, fun(_Node, _Idx) ->ws end).

-spec 'ws'(input(), index()) -> parse_result().
'ws'(Input, Index) ->
  p(Input, Index, 'ws', fun(I,D) -> (p_charclass(<<"[\t\s]">>))(I,D) end, fun(_Node, _Idx) ->ws end).


transform(_,Node,_Index) -> Node.
-file("peg_includes.hrl", 1).
-type index() :: {{line, pos_integer()}, {column, pos_integer()}}.
-type input() :: binary().
-type parse_failure() :: {fail, term()}.
-type parse_success() :: {term(), input(), index()}.
-type parse_result() :: parse_failure() | parse_success().
-type parse_fun() :: fun((input(), index()) -> parse_result()).
-type xform_fun() :: fun((input(), index()) -> term()).

-spec p(input(), index(), atom(), parse_fun(), xform_fun()) -> parse_result().
p(Inp, StartIndex, Name, ParseFun, TransformFun) ->
  case get_memo(StartIndex, Name) of      % See if the current reduction is memoized
    {ok, Memo} -> %Memo;                     % If it is, return the stored result
      Memo;
    _ ->                                        % If not, attempt to parse
      Result = case ParseFun(Inp, StartIndex) of
        {fail,_} = Failure ->                       % If it fails, memoize the failure
          Failure;
        {Match, InpRem, NewIndex} ->               % If it passes, transform and memoize the result.
          Transformed = TransformFun(Match, StartIndex),
          {Transformed, InpRem, NewIndex}
      end,
      memoize(StartIndex, Name, Result),
      Result
  end.

-spec setup_memo() -> ets:tid().
setup_memo() ->
  put({parse_memo_table, ?MODULE}, ets:new(?MODULE, [set])).

-spec release_memo() -> true.
release_memo() ->
  ets:delete(memo_table_name()).

-spec memoize(index(), atom(), parse_result()) -> true.
memoize(Index, Name, Result) ->
  Memo = case ets:lookup(memo_table_name(), Index) of
              [] -> [];
              [{Index, Plist}] -> Plist
         end,
  ets:insert(memo_table_name(), {Index, [{Name, Result}|Memo]}).

-spec get_memo(index(), atom()) -> {ok, term()} | {error, not_found}.
get_memo(Index, Name) ->
  case ets:lookup(memo_table_name(), Index) of
    [] -> {error, not_found};
    [{Index, Plist}] ->
      case proplists:lookup(Name, Plist) of
        {Name, Result}  -> {ok, Result};
        _  -> {error, not_found}
      end
    end.

-spec memo_table_name() -> ets:tid().
memo_table_name() ->
    get({parse_memo_table, ?MODULE}).

-ifdef(p_eof).
-spec p_eof() -> parse_fun().
p_eof() ->
  fun(<<>>, Index) -> {eof, [], Index};
     (_, Index) -> {fail, {expected, eof, Index}} end.
-endif.

-ifdef(p_optional).
-spec p_optional(parse_fun()) -> parse_fun().
p_optional(P) ->
  fun(Input, Index) ->
      case P(Input, Index) of
        {fail,_} -> {[], Input, Index};
        {_, _, _} = Success -> Success
      end
  end.
-endif.

-ifdef(p_not).
-spec p_not(parse_fun()) -> parse_fun().
p_not(P) ->
  fun(Input, Index)->
      case P(Input,Index) of
        {fail,_} ->
          {[], Input, Index};
        {Result, _, _} -> {fail, {expected, {no_match, Result},Index}}
      end
  end.
-endif.

-ifdef(p_assert).
-spec p_assert(parse_fun()) -> parse_fun().
p_assert(P) ->
  fun(Input,Index) ->
      case P(Input,Index) of
        {fail,_} = Failure-> Failure;
        _ -> {[], Input, Index}
      end
  end.
-endif.

-ifdef(p_seq).
-spec p_seq([parse_fun()]) -> parse_fun().
p_seq(P) ->
  fun(Input, Index) ->
      p_all(P, Input, Index, [])
  end.

-spec p_all([parse_fun()], input(), index(), [term()]) -> parse_result().
p_all([], Inp, Index, Accum ) -> {lists:reverse( Accum ), Inp, Index};
p_all([P|Parsers], Inp, Index, Accum) ->
  case P(Inp, Index) of
    {fail, _} = Failure -> Failure;
    {Result, InpRem, NewIndex} -> p_all(Parsers, InpRem, NewIndex, [Result|Accum])
  end.
-endif.

-ifdef(p_choose).
-spec p_choose([parse_fun()]) -> parse_fun().
p_choose(Parsers) ->
  fun(Input, Index) ->
      p_attempt(Parsers, Input, Index, none)
  end.

-spec p_attempt([parse_fun()], input(), index(), none | parse_failure()) -> parse_result().
p_attempt([], _Input, _Index, Failure) -> Failure;
p_attempt([P|Parsers], Input, Index, FirstFailure)->
  case P(Input, Index) of
    {fail, _} = Failure ->
      case FirstFailure of
        none -> p_attempt(Parsers, Input, Index, Failure);
        _ -> p_attempt(Parsers, Input, Index, FirstFailure)
      end;
    Result -> Result
  end.
-endif.

-ifdef(p_zero_or_more).
-spec p_zero_or_more(parse_fun()) -> parse_fun().
p_zero_or_more(P) ->
  fun(Input, Index) ->
      p_scan(P, Input, Index, [])
  end.
-endif.

-ifdef(p_one_or_more).
-spec p_one_or_more(parse_fun()) -> parse_fun().
p_one_or_more(P) ->
  fun(Input, Index)->
      Result = p_scan(P, Input, Index, []),
      case Result of
        {[_|_], _, _} ->
          Result;
        _ ->
          {fail, {expected, Failure, _}} = P(Input,Index),
          {fail, {expected, {at_least_one, Failure}, Index}}
      end
  end.
-endif.

-ifdef(p_label).
-spec p_label(atom(), parse_fun()) -> parse_fun().
p_label(Tag, P) ->
  fun(Input, Index) ->
      case P(Input, Index) of
        {fail,_} = Failure ->
           Failure;
        {Result, InpRem, NewIndex} ->
          {{Tag, Result}, InpRem, NewIndex}
      end
  end.
-endif.

-ifdef(p_scan).
-spec p_scan(parse_fun(), input(), index(), [term()]) -> {[term()], input(), index()}.
p_scan(_, <<>>, Index, Accum) -> {lists:reverse(Accum), <<>>, Index};
p_scan(P, Inp, Index, Accum) ->
  case P(Inp, Index) of
    {fail,_} -> {lists:reverse(Accum), Inp, Index};
    {Result, InpRem, NewIndex} -> p_scan(P, InpRem, NewIndex, [Result | Accum])
  end.
-endif.

-ifdef(p_string).
-spec p_string(binary()) -> parse_fun().
p_string(S) ->
    Length = erlang:byte_size(S),
    fun(Input, Index) ->
      try
          <<S:Length/binary, Rest/binary>> = Input,
          {S, Rest, p_advance_index(S, Index)}
      catch
          error:{badmatch,_} -> {fail, {expected, {string, S}, Index}}
      end
    end.
-endif.

-ifdef(p_anything).
-spec p_anything() -> parse_fun().
p_anything() ->
  fun(<<>>, Index) -> {fail, {expected, any_character, Index}};
     (Input, Index) when is_binary(Input) ->
          <<C/utf8, Rest/binary>> = Input,
          {<<C/utf8>>, Rest, p_advance_index(<<C/utf8>>, Index)}
  end.
-endif.

-ifdef(p_charclass).
-spec p_charclass(string() | binary()) -> parse_fun().
p_charclass(Class) ->
    {ok, RE} = re:compile(Class, [unicode, dotall]),
    fun(Inp, Index) ->
            case re:run(Inp, RE, [anchored]) of
                {match, [{0, Length}|_]} ->
                    {Head, Tail} = erlang:split_binary(Inp, Length),
                    {Head, Tail, p_advance_index(Head, Index)};
                _ -> {fail, {expected, {character_class, binary_to_list(Class)}, Index}}
            end
    end.
-endif.

-ifdef(p_regexp).
-spec p_regexp(binary()) -> parse_fun().
p_regexp(Regexp) ->
    {ok, RE} = re:compile(Regexp, [unicode, dotall, anchored]),
    fun(Inp, Index) ->
        case re:run(Inp, RE) of
            {match, [{0, Length}|_]} ->
                {Head, Tail} = erlang:split_binary(Inp, Length),
                {Head, Tail, p_advance_index(Head, Index)};
            _ -> {fail, {expected, {regexp, binary_to_list(Regexp)}, Index}}
        end
    end.
-endif.

-ifdef(line).
-spec line(index() | term()) -> pos_integer() | undefined.
line({{line,L},_}) -> L;
line(_) -> undefined.
-endif.

-ifdef(column).
-spec column(index() | term()) -> pos_integer() | undefined.
column({_,{column,C}}) -> C;
column(_) -> undefined.
-endif.

-spec p_advance_index(input() | unicode:charlist() | pos_integer(), index()) -> index().
p_advance_index(MatchedInput, Index) when is_list(MatchedInput) orelse is_binary(MatchedInput)-> % strings
  lists:foldl(fun p_advance_index/2, Index, unicode:characters_to_list(MatchedInput));
p_advance_index(MatchedInput, Index) when is_integer(MatchedInput) -> % single characters
  {{line, Line}, {column, Col}} = Index,
  case MatchedInput of
    $\n -> {{line, Line+1}, {column, 1}};
    _ -> {{line, Line}, {column, Col+1}}
  end.
