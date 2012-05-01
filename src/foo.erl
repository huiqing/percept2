-module(foo).


-export([a1/1]).

-compile(export_all).

-export([create_file_slow/2]).

a1(X) -> 
   spawn(fun()->b(X) end).

b(X) ->
    [foo(lists:seq(1,10))|| Y<-lists:seq(1, X)].
   

c(Y) ->
    [X+1||X<-lists:seq(1, Y)].
 

e(Z) ->
     ok.

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


fac(0)->1;
fac(N)-> N * fac(N-1). 


fib(0) -> 0;
fib(1) -> 1; 
fib(N) -> fib(N-1) ++ fib(N-1).


foo(Fs) ->
    foo(Fs, []).
foo([], Out) ->
    lists:reverse(Out);
foo([F|Fs], Out) ->
    NewF = bar(F),
    foo(Fs, [NewF|Out]) ++ [].

bar(X) ->
    X+2.
