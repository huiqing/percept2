%%%-------------------------------------------------------------------
%%% @author jose <>
%%% @copyright (C) 2012, jose
%%% @doc
%%% Testing stuff
%%% @end
%%% Created : 15 Jun 2012 by jose <>
%%%-------------------------------------------------------------------
-module(foo).


foo(X1) ->
    X1.

invent_creator(DocId) when is_binary(DocId) ->
    L = byte_size(DocId) - 6,
    <<_:L/binary, Part/binary>> = DocId,
    << <<(min($9, X))>> || <<X>> <= Part >>. %% Line with the problem

