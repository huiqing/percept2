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
                         percept2_db, 
                         egd_font,
                         percept2_dist,  
                         wrangler_comment_scan,
                         egd_png,
                         percept2_dot,
                         wrangler_epp,
                         egd_primitives,
                         percept2_graph,
                         wrangler_epp_dodger,
                         egd_render,    
                         percept2_html, 
                         wrangler_io,
                         gen_plt_script,
                         percept2_image,   
                         modulegraph.dot   
                         percept2_orbit,    
                         wrangler_parse,
                         wrangler_recomment,
                         modulegraph.png     
                         percept2_profile,  
                         wrangler_scan,
                         percept2,           
                         percept2_report,  
                         wrangler_scan_with_layout,
                         percept2_analyzer, 
                         percept2_sampling, 
                         wrangler_syntax,
                         percept2_code_server,
                         percept2_utils,
                         percept2_data_gen,  
                         wrangler_ast_gen                         
                        ]},
         {registered,	[percept2_db,percept2_port,
                         percept2_code_server,
                         percept2_httpd,
                         percept2_sampling]},
	 {applications,	[kernel,stdlib, inets]},
	 {env,		[]}
	]}.



