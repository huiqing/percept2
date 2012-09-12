-module(foo3).

-export([a1/0]).

a1() ->
    b().
b() ->
    c(),
    d().
c() -> ok.
d() ->
    e(),
    c().
e() ->
    f(). 
f() -> ok.

%% -export([create_file_slow/2]).

%% create_file_slow(Name, N) when integer(N), N >= 0 ->
%%     {ok, FD} = 
%%         file:open(Name, [raw, write, delayed_write, binary]),
%%     if N > 256 ->
%%             ok = file:write(FD, 
%%                             lists:map(fun (X) -> <<X:32/unsigned>> end,
%%                             lists:seq(0, 255))),
%%             ok = create_file_slow(FD, 256, N);
%%        true ->
%%             ok = create_file_slow(FD, 0, N)
%%     end,
%%     ok = file:close(FD).

%% create_file_slow(FD, M, M) ->
%%     ok;
%% create_file_slow(FD, M, N) ->
%%     ok = file:write(FD, <<M:32/unsigned>>),
%%     create_file_slow(FD, M+1, N).

n() ->
    ok.