%%
%% %CopyrightBegin%
%% 
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

{application,percept2,
	[{description, 	"An Enhanced version of the Erlang Concurrency Profiling Tool Percept"},
	 {vsn,		"1.0"},
 	 {modules,	[egd,
                         egd_font,
                         egd_png,
                         egd_primitives,
                         egd_render,
                         gen_plt_script,
                         percept2,
                         percept2_analyzer,
                         percept2_data_gen,
                         percept2_db,
                         percept2_dist,
                         percept2_dot,
                         percept2_graph,
                         percept2_html,
                         percept2_image,        
                         percept2_orbit,
                         percept2_profile,
                         percept2_sampling,
                         percept2_utils]},
         {registered,	[percept2_db,percept2_port]},
	 {applications,	[kernel,stdlib, inets]},
	 {env,		[]}
	]}.



