-module(foo).


-export([a1/1]).

-compile(export_all).

-export([create_file_slow/2]).

a1(X) -> 
   spawn(fun()->b() end).

%% a1(X) -> 
%%   b().


foo() ->
     if true  ->
             1;
        true, 1>0 -> 9
     end.

b() ->
    c(),
    d(),
    d().
c() -> ok.
d() ->
    e(),
    c().   
e() ->
    f(). 
f() -> ok.


test() ->
    spawn(foo, create_file_slow, [junk, 260]).

create_file_slow(Name, N) when integer(N), N >= 0 ->
    {ok, FD} = 
        file:open(Name, [raw, write, delayed_write, binary]),
    if N > 256 ->
            ok = file:write(FD, 
                             lists:map(fun (X) -> <<X:32/unsigned>> end,
                              lists:seq(0, 2))),
            ok = create_file_slow(FD, 256, N);
       true -> 
            ok = create_file_slow(FD, 0, N)
    end,
    ok = file:close(FD).

create_file_slow(FD, M, M) ->
    ok;
create_file_slow(FD, M, N) ->
    ok = file:write(FD, <<M:32/unsigned>>),
    create_file_slow(FD, M+1, N).
