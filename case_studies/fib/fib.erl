-module(fib).

-compile(export_all).

fib(N) ->
    fib(N, fun(X) -> X <20 end).
                   
fib(0,_T) -> 0;
fib(1,_T) -> 1;
fib(N,T) ->
    {L,R} = {N-1, N-2},
    case T(N) of
        true -> fib(L, T) + fib(R, T);
        false ->
            spawn(?MODULE,fib_worker, [self(),L,T]),
            spawn(?MODULE,fib_worker, [self(),R,T]),
            S1 = receive R1 -> R1 end,
            S2 = receive R2 -> R2 end,
            S1 + S2 
    end.

fib_worker(Pid, N,T) ->
    Pid ! fib(N,T).


               
