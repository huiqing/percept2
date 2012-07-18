-module(foo).

-compile(export_all).

-export([test/0, create_file_slow/2]).

test() ->
    spawn(foo, create_file_slow, [junk,300]).

create_file_slow(Name, N) when integer(N), N >= 0 ->
    {ok, FD} = 
        file:open(Name, [raw, write, delayed_write, binary]),
    if N > 256 ->
            ok = file:write(FD, 
                            lists:map(fun (X) -> <<X:32/unsigned>> end,
                            lists:seq(0, 255))),
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

