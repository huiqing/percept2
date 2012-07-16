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

-compile(export_all).

pmap(Fun, List) ->
    Parent = self(),
    [receive {Pid, Result} -> Result end ||
        Pid <- [spawn_link(?MODULE, pmap_1, [Fun, Parent, X])
                || X <- List]].

pmap_1(Fun, Parent, X) ->Parent ! {self(), Fun(X)}.


pforeach(Fun, List) ->
    Self = self(),
    Pid = spawn_link(?MODULE, pforeach_0, [Self, Fun, List]),
    receive 
        Pid -> ok
    end.
pforeach_0(Parent, Fun, List) ->
    Self = self(),
    _Pids = [spawn_link(?MODULE, pforeach_1, [Fun, Self, X])
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
