% Copyright (c) 2012 the authors listed at the following URL, and/or
% the authors of referenced articles or incorporated external code:
% http://en.literateprograms.org/Merge_sort_(Erlang)?action=history&offset=20061124010712
% 
% Permission is hereby granted, free of charge, to any person obtaining
% a copy of this software and associated documentation files (the
% "Software"), to deal in the Software without restriction, including
% without limitation the rights to use, copy, modify, merge, publish,
% distribute, sublicense, and/or sell copies of the Software, and to
% permit persons to whom the Software is furnished to do so, subject to
% the following conditions:
% 
% The above copyright notice and this permission notice shall be
% included in all copies or substantial portions of the Software.
% 
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
% IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
% CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
% TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
% SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
% 
% Retrieved from: http://en.literateprograms.org/Merge_sort_(Erlang)?oldid=8158

-module(mergesort).
-export([msort/2, msort_lte/1, msort_gte/1]).
-export([split/1]).
-export([merge/3]).

-compile(export_all).

split(Ls) ->
    split(Ls, Ls, []).

split([], Ls1, Ls2) ->
    {lists:reverse(Ls2) , Ls1};

split([_], Ls1, Ls2) ->
    {lists:reverse(Ls2) , Ls1};

split([_,_|TT], [Ls1_H | Ls1_T], Ls2) ->
    split(TT, Ls1_T, [Ls1_H | Ls2]).



merge(_, [], Ls2) ->
    Ls2;
merge(_, Ls1, []) ->
    Ls1;
merge(Rel, [H1|T1], [H2|T2]) ->
    case Rel(H1, H2) of
	true ->
	    [H1 | merge(Rel, T1, [H2|T2])];
	false ->
	    [H2 | merge(Rel, [H1|T1], T2)]
    end.

msort(_, []) ->
    [];
msort(_, [H]) ->
    [H];
msort(Rel, Ls) ->
    {Half1 , Half2} = split(Ls),
    L1 = msort(Rel, Half1),
    L2 = msort(Rel, Half2),
    merge(Rel, L1, L2).
    % merge(Rel, msort(Rel, Half1), msort(Rel, Half2)).

% Parameterize msort with commonly-used predicates
lte(X, Y) ->
    (X < Y) or (X == Y).

gte(X, Y) ->
    (X > Y) or (X == Y).
 
msort_lte(Ls) ->
    spawn(fun()->mergesort:msort(fun lte/2, Ls) end).
    
msort_gte(Ls) ->
    spawn_link(mergesort, msort, [fun gte/2,Ls]).
 
