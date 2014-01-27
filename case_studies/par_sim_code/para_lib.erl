-module(para_lib).

-export([pmap/2,
         pmap/3,
         pforeach/2,
         pforeach/3]).

-export([pmap_0/4, 
         pmap_1/3,
         pforeach_0/4,
         pforeach_1/3]).

-compile(export_all).

%%-------------------------------%%
%%      parallel map             %%
%%-------------------------------%%
pmap(Fun, List) ->
    pmap(Fun, List, 1).

pmap(Fun, List, Size) ->
    Parent = self(),
    Pid = spawn_link(?MODULE, pmap_0, [Parent, Fun, List, Size]),
    receive
        {Pid, Res}-> Res
    end.

pmap_0(Parent, Fun, List,Size) when Size=<1->
    Self = self(),
    Pids=[spawn_link(?MODULE, pmap_1, [Fun, Self, X])
             ||X<-List],
    Res=[receive {Pid, Result} ->
             Result end|| Pid<-Pids],
    Parent!{Self, Res};
pmap_0(Parent, Fun, List, Size) ->
    Self = self(),
    ChoppedList = chop_a_list(List, Size),
    Pids=[spawn_link(?MODULE, pmap_2, [Fun, Self, SubList])
          ||SubList<-ChoppedList],
    Res=[receive {Pid, Result} ->
             Result end|| Pid<-Pids],
    Parent!{Self, lists:append(Res)}.


pmap_1(Fun, Parent, X) ->
    Res = (catch Fun(X)),
    Parent!{self(), Res}.

pmap_2(Fun, Parent, SubList) ->
    Res = (catch lists:map(fun(X) ->
                                   Fun(X)
                           end, SubList)),
    Parent!{self(), Res}.
%%-------------------------------%%
%%      parallel foreach         %%
%%-------------------------------%%
pforeach(Fun, List) ->
    pforeach(Fun, List,1).

pforeach(Fun, List, Size)->
    Self = self(),
    Pid = spawn_link(?MODULE, pforeach_0, [Self, Fun, List, Size]),
    receive 
        Pid -> ok
    end.
pforeach_0(Parent, Fun, List, Size) when Size =<1->
    Self = self(),
    _Pids = [spawn_link(?MODULE, pforeach_1, [Fun, Self, X])
             || X <- List],
    pforeach_wait(Self, length(List)),
    Parent ! Self;
pforeach_0(Parent, Fun, List, Size) when Size>1 ->
    Self = self(),
    ChoppedList = chop_a_list(List, Size),
    _Pids = [spawn_link(?MODULE, pforeach_2, [Fun, Self, SubList])
             || SubList <- ChoppedList],
    pforeach_wait(Self, length(ChoppedList)),
    Parent ! Self.

pforeach_1(Fun, Parent, X) ->
    _ =  (catch Fun(X)),
    Parent ! Parent.

pforeach_2(Fun, Parent, SubList) ->
    _ = (catch lists:foreach(fun(X) ->
                                     Fun(X)
                             end, SubList)),
    Parent!Parent.

pforeach_wait(_S,0) -> ok;
pforeach_wait(S,N) ->
    receive
        S -> pforeach_wait(S,N-1)
    end.

%%-----------------------------------------%%
%%      Utility Functions                  %%
%%-----------------------------------------%%
chop_a_list(List, 1) -> List;
chop_a_list(List, Size) ->
    Len = length(List),
    Chops0 = Len/Size, 
    Chops= case Chops0 =< round(Chops0) of 
               true ->
                   round(Chops0)-1;
               _ -> round(Chops0)
           end,
    chop_a_list(List, 0, Chops, Size, []).

chop_a_list([], _, _, _, Acc) ->
    lists:reverse(Acc);
chop_a_list(List, Count, Chops, _Size, Acc) 
  when Count==Chops -> 
    lists:reverse([List|Acc]);
chop_a_list(List, Count, Chops, Size, Acc) -> 
    {List1, List2}=lists:split(Size, List),
    chop_a_list(List2, Count+1, Chops, 
                Size, [List1|Acc]).
        

                                                   
    
     
