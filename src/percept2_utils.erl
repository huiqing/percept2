%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%%     %% Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%     %% Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%     %% Neither the name of the copyright holders nor the
%%       names of its contributors may be used to endorse or promote products
%%       derived from this software without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ''AS IS''
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
%% BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%% ======================================================================
%%
%% Author contact: hl@kent.ac.uk.
%% @private

-module(percept2_utils).

-export([pmap/2, pforeach/2]).

-export([pmap_0/3, pmap_1/3,
         pforeach_0/3, pforeach_1/3,
         pforeach_wait/2]).

-export([spawn/1,spawn/2, spawn/3, spawn/4,
         spawn_link/1, spawn_link/2,
         spawn_link/3, spawn_link/4,
         spawn_monitor/1, spawn_monitor/3,
         spawn_opt/2, spawn_opt/3,
         spawn_opt/4, spawn_opt/5]).

-include("../include/percept2.hrl").

pmap(Fun, List) ->
    Parent = self(),
    Pid = erlang:spawn_link(?MODULE, pmap_0, [Parent, Fun, List]),
    receive
        {Pid, Res}-> Res
    end.

pmap_0(Parent, Fun, List) ->
    Self = self(),
    Pids=lists:map(fun(X) ->
                       erlang:spawn_link(?MODULE, pmap_1, [Fun, Self, X])
                    end, List),
    Res=[receive {Pid, Result} ->
             Result end|| Pid<-Pids],
    Parent!{Self, Res}.

pmap_1(Fun, Parent, X) ->
    Res = (catch Fun(X)),
    Parent!{self(), Res}.


pforeach(Fun, List) ->
    Self = self(),
    Pid = erlang:spawn_link(?MODULE, pforeach_0, [Self, Fun, List]),
    receive 
        Pid -> ok
    end.
pforeach_0(Parent, Fun, List) ->
    Self = self(),
    _Pids = [erlang:spawn_link(?MODULE, pforeach_1, [Fun, Self, X])
             || X <- List],
    pforeach_wait(Self, length(List)),
    Parent ! Self.

pforeach_1(Fun, Self, X) ->
    _ =  (catch Fun(X)),
    Self ! Self.

pforeach_wait(_S,0) -> ok;
pforeach_wait(S,N) ->
    receive
        S -> pforeach_wait(S,N-1)
    end.

%% Use refactoring to replace the uses of erlang:spawn/spawn_link to 
%% the uses of percept2:spawn/spawn_link.
%% HOW ABOUT RECURSIVE FUNCTION CALLS?
spawn(Fun) ->
    percept2_spawn(spawn, [Fun]).

spawn(Node, Fun) ->
    percept2_spawn(spawn, [Node, Fun]).

spawn(M, F, A) ->
    percept2_spawn(spawn, [M,F,A]).

spawn(Node, M, F, A) ->
    percept2_spawn(spawn, [Node, M, F, A]).

spawn_link(Fun) ->
    percept2_spawn(spawn_link,[Fun]).

spawn_link(Node, Fun) ->
    percept2_spawn(spawn_link, [Node, Fun]).

spawn_link(M, F, A) ->
    percept2_spawn(spawn_link, [M,F,A]).

spawn_link(Node, M, F, A) ->
    percept2_spawn(spawn_link, [Node, M, F, A]).

spawn_monitor(Fun) ->
    percept2_spawn(spawn_monitor, [Fun]).

spawn_monitor(Module, Function, Args) ->
    percept2_spawn(spawn_monitor, [Module, Function, Args]).

spawn_opt(Fun, Options) ->
    percept2_spawn(spawn_opt, [Fun, Options]).

spawn_opt(Node, Fun, Options) ->
    percept2_spawn(spawn_opt, [Node, Fun, Options]).

spawn_opt(Module, Function, Args, Options) ->
     percept2_spawn(spawn_opt, [Module, Function, Args, Options]).

spawn_opt(Node, Module, Function, Args, Options) ->
     percept2_spawn(spawn_opt, [Node, Module, Function, Args, Options]).


percept2_spawn(SpawnFunc, Args) ->
    Entry=case Args of 
              [M, F, Args1]->
                  {M,F, length(Args1)};
              [Node, M, F, Args1] ->
                  [Node, M, F, length(Args1)];
              Others -> 
                  Others
          end,
    Silent = get_slient_value(Entry),
    Pid=erlang:apply(erlang, SpawnFunc, Args),
    if Silent ->
            erlang:trace(Pid, false, [call, return_to]);
       true -> ok       
    end,
    Pid.

get_slient_value(Entry) ->
    Tab = ?percept2_spawn_tab,
    case ets:info(Tab) of 
        undefined ->
            false;
        _  ->
            case ets:lookup(Tab, Entry) of
                [] ->
                    ets:insert(Tab, {Entry, 1, 1}),
                    false;
                [{Entry, Count, Rate}] ->
                    case  (Count + 1) rem Rate of
                        0 ->
                            ets:update_counter(Tab, Entry,[{2,-Count},{3,1}]),
                            false;
                        _ ->
                            ets:update_counter(Tab, Entry,[{2,1}]),
                            true
                    end
            end
    end.
