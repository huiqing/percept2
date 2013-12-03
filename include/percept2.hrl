%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2010. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%% 

%%% -------------------	%%%
%%% Type definitions	%%%
%%% -------------------	%%%
-type timestamp() :: {non_neg_integer(), non_neg_integer(), non_neg_integer()}.
-type true_mfa() :: {atom(), atom(), byte() | list()}.
-type state() :: 'active' | 'inactive'.
-type scheduler_id() :: non_neg_integer().

-type pid_value()::{pid, {non_neg_integer(), non_neg_integer()|atom(), non_neg_integer()}}.

%% for removing warnings from dialyzer.
-type special_atom()::'_'|'$0'|'$1'|'$2'|'$3'|'$4'|'$5'|'$6'.
%%% -------------------	%%%
%%% 	Records		%%%
%%% -------------------	%%%
-record(activity, {
          timestamp 		 :: timestamp()|special_atom(), 
          id 			 :: pid_value() | port()|special_atom(),
          state = undefined	 :: state() | 'undefined'|special_atom(),
          where = undefined	 :: true_mfa() | 'undefined'|'suspend'|'garbage_collect'
                                  |special_atom(),
          runnable_procs=0       :: integer()|special_atom(),
          runnable_ports=0       :: integer()|special_atom(),
          in_out = []            :: [{atom(), timestamp()}]|special_atom()
         }).

-record(scheduler, {
          timestamp          :: timestamp()|special_atom(),
          id                 :: scheduler_id()|special_atom(),
          state = undefined  :: state()|'undefined'|special_atom(),
          active_scheds = 0  :: non_neg_integer()|special_atom()
          }).

-record(information, {
          id			 :: pid_value() | port()|special_atom()|{pid, special_atom()},
          node = nonode          :: atom(),
          name = undefined	 :: atom()| string()|'undefined'|special_atom(), 
          entry = undefined	 :: true_mfa()|'undefined'|'suspend'|'garbage_collect'|
                                    special_atom()|
                                    {special_atom(),special_atom(), special_atom()}, 
          start = undefined 	 :: timestamp()|'undefined'|special_atom(),
          stop = undefined	 :: timestamp()|'undefined'|special_atom(), 
          parent = undefined 	 :: pid_value()|'undefined'|special_atom(),
          ancestors =[]          :: [pid_value()]|special_atom(),
          rq_history=[]          :: [{timestamp(), non_neg_integer()}]|special_atom(),
          children = []		 :: [pid_value()]|special_atom(),
          msgs_received ={0, 0}  :: {non_neg_integer(), non_neg_integer()}|special_atom(),
          msgs_sent     ={0, 0}  :: {non_neg_integer(), non_neg_integer()}|special_atom(),
          gc_time      = 0       :: non_neg_integer()|special_atom(),
          accu_runtime = 0       :: non_neg_integer()|special_atom(),
          hidden_pids = []       :: [pid_value()]|special_atom(),
          hidden_proc_trees=[]    :: [term()]|special_atom()
	}).
 
-record(inter_proc, {
          timed_from    ::{timestamp(),node(), pid()|pid_value()}|{special_atom(), special_atom(), special_atom()},
          to            ::{node(), pid()}|{special_atom(), special_atom()}|special_atom(),
          msg_size      ::pos_integer()|special_atom()
         }).


-record(inter_sched, {
          from_sched_with_ts  ::{timestamp(),node()}|{special_atom(), special_atom()},
          dest_sched    ::node()|special_atom(),
          msg_size    ::pos_integer()|special_atom()
         }).

-record(funcall_info, {
          id                 ::{pid_value(),timestamp(), timestamp()}|
                               {special_atom(),special_atom(), special_atom()},       
          func               ::true_mfa()|special_atom()|suspend|garbage_collect
         }).
                 
-record(fun_calltree, {
          id                     ::{pid_value()|special_atom(), true_mfa()|undefined
                                    |'suspend'|'garbage_collect'|special_atom(), 
                                    timestamp()|special_atom()}|
                                   {pid_value()|special_atom(), true_mfa()|undefined
                                    |'suspend'|'garbage_collect'|special_atom(), 
                                    true_mfa()|special_atom()}|
                                   {special_atom(), special_atom(), special_atom()}|
                                   special_atom(),
          cnt =1                 ::non_neg_integer()|special_atom(),
          rec_cnt=0              ::non_neg_integer()|special_atom(),
          called =[]             ::[#fun_calltree{}]|special_atom(),
          acc_time = 0           ::non_neg_integer()|special_atom(),
          start_ts = undefined   ::timestamp()|undefined|special_atom(),
          end_ts = undefined     ::timestamp()|undefined|special_atom()
         }).

-record(fun_info, {
          id                   ::{pid_value()|special_atom(), any()},
          callers = []         ::any(), %% ::[{true_mfa()|undefined, non_neg_integer()}]|special_atom(),
          called = []          ::any(), %%[{true_mfa(), non_neg_integer()}]|special_atom(),
          start_ts = undefined ::any(), %%timestamp()|undefined|special_atom(),
          end_ts = undefined   ::any(), %%timestamp()|undefinedspecial_atom(),
          call_count = 0       ::non_neg_integer()|special_atom(),
          acc_time = 0         ::non_neg_integer()|special_atom()
         }).


-record(msg_queue_len, {
          pid         ::pid_value()|port()|special_atom()|{pid, special_atom()},
          timestamp   ::timestamp()|special_atom(),
          len =0      ::non_neg_integer()
         }).

-type s_group_op()::new_s_group|delete_s_group|add_nodes|remove_nodes.

-record(s_group_info, 
        {timed_node:: {timestamp(),node()},
         op :: {s_group_op(), [term()]}
        }).
          
-record(history_html, {
          id         ::string(),
          content    ::any()
         }).


%%% -------------------	%%%
%%% 	Macros		%%%
%%% -------------------	%%%
-define(seconds(EndTs,StartTs), timer:now_diff(EndTs, StartTs)/1000000).

-define(percept2_spawn_tab, percept2_spawn).
%%-define(debug, 9).

%%-define(debug, -1).

-ifdef(debug). 
dbg(Level, F, A) when Level >= ?debug ->
    io:format(F, A),
    ok;
dbg(_, _, _) ->
    ok.
-define(dbg(Level, F, A), dbg((Level), (F), (A))).
-else.
-define(dbg(Level, F, A), ok).
-endif.
