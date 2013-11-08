%% 
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2007-2009. All Rights Reserved.
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

-module(percept2_image).
-export([proc_lifetime/5,
         percentage/3,
         calltime_percentage/4,
         query_fun_time/4,
         graph/4, 
         graph/5, 
         activities/3, 
         activities/4,
         inter_node_message_image/5]).

-record(graph_area, {x = 0, y = 0, width, height}).

-compile(export_all).

-compile(inline).

-include("../include/percept2.hrl").
%%% -------------------------------------
%%% GRAF
%%% -------------------------------------

%% graph(Widht, Height, Range, Data)

graph(Width,Height,{RXmin, RYmin, RXmax, RYmax},Data,HO) ->
     case Data of
         [] -> <<>>;
         _ ->
             {_, Proc, Port}=lists:last(Data),
             Last = {RXmax, Proc, Port},
             Data2=[{X, Y1 + Y2}||{X, Y1, Y2} <- [Last|Data]],
             Data3 =lists:reverse([Last|lists:reverse(Data)]),
             MinMax = minmax(Data2),
             {Xmin, Ymin, Xmax, Ymax} = MinMax,
             graf1(Width, Height,{	lists:min([RXmin, Xmin]),
                                        lists:min([RYmin, Ymin]),
                                        lists:max([RXmax, Xmax]),
                                        lists:max([RYmax, Ymax])}, 
                   Data3, HO)
     end.
     
%% graph(Widht, Height, Data) = Image
%% In:
%%	Width = integer(),
%%	Height = integer(),
%%	Data = [{Time, Procs, Ports}]
%%	Time = float()
%%	Procs = integer()
%%	Ports = integer()
%% Out:
%%	Image = binary()
graph(Width, Height, [], _) ->
    error_graph(Width, Height,"No trace data recorded.");
graph(Width,Height,Data,HO) ->
    Data2 = [{X, Y1 + Y2} || {X, Y1, Y2} <- Data],
    Bounds = minmax(Data2),
    graf1(Width,Height,Bounds,Data,HO).

error_graph(Width, Height, Text) ->
    %% Initiate Image
    Image = egd:create(round(Width/2), round(Height/2)),
    Font = get_font(),
    egd:text(Image, {200, 100}, Font, Text,  egd:color(Image, {255, 0, 0})),
    Binary = egd:render(Image, png),
    egd:destroy(Image),
    Binary.

    
graf1(Width,Height,{Xmin, Ymin, Xmax, Ymax},Data,HOffset) ->
    % Calculate areas
    HO = HOffset,
    GrafArea   = #graph_area{x = HO, y = 4, width = Width -HO, height = Height - 17},
    XticksArea = #graph_area{x = HO, y = Height - 13, width = Width - HO, height = 13},
    YticksArea = #graph_area{x = 1,  y = 4, width = HO, height = Height - 17},
    
    %% Initiate Image

    Image = egd:create(Width, Height),
 
    %% Set colors
    
    Black = egd:color(Image, {0, 0, 0}),
    ProcColor = egd:color(Image, {0, 255, 0}),
    PortColor = egd:color(Image, {255, 0, 0}),
    
    %% Draw graf, xticks and yticks
    draw_graf(Image, Data, {Black, ProcColor, PortColor}, GrafArea, {Xmin, Ymin, Xmax, Ymax}),
    draw_xticks(Image, Black, XticksArea, {Xmin, Xmax}, Data),
    draw_yticks(Image, Black, YticksArea, {Ymin, Ymax}, HO-20),
    
    %% Kill image and return binaries
    Binary = egd:render(Image, png),
    egd:destroy(Image),
    Binary.

%% draw_graf(Image, Data, Color, GraphArea, DataBounds)
%% Image, port to Image
%% Data, list of three tuple data, (X, Y1, Y2)
%% Color, {ForegroundColor, ProcFillColor, PortFillColor}
%% DataBounds, {Xmin, Ymin, Xmax, Ymax}

draw_graf(Im, Data, Colors, GA = #graph_area{x = X0, y = Y0, width = Width, height = Height}, {Xmin, _Ymin, Xmax, Ymax}) ->
    Dx = (Width)/(Xmax - Xmin),
    Dy = (Height)/(Ymax),
    Plotdata = [{trunc(X0 + X*Dx - Xmin*Dx), trunc(Y0 + Height - Y1*Dy), trunc(Y0 + Height - (Y1 + Y2)*Dy)} || {X, Y1, Y2} <- Data],
    Data1=remove_duplicates(Plotdata),
    draw_graf(Im, Data1, Colors, GA).



draw_graf(Im, [{X1, Yproc1, Yport1}, {X2, Yproc2, Yport2}|Data], C, GA) when X2 - X1 < 1 ->
    if {Yproc1, Yport1} == {Yproc2, Yport2} ->
            draw_graf(Im, [{X2, Yproc2, Yport2}|Data], C, GA);
       true ->
            draw_graf(Im, [{X1, [{Yproc2, Yport2},{Yproc1, Yport1}]}|Data], C, GA)
    end;
draw_graf(Im, [{X1, Ys1}, {X2, Yproc2, Yport2}|Data], C, GA) when X2 - X1 < 1, is_list(Ys1) ->
    case lists:member({Yproc2, Yport2}, Ys1) of
        true ->
            draw_graf(Im, [{X1, Ys1}|Data], C, GA);
        false ->
            draw_graf(Im, [{X1, [{Yproc2, Yport2}|Ys1]}|Data], C, GA)
    end;
draw_graf(Im, [{X1, Yproc1, Yport1}, {X2, Yproc2, Yport2}|Data], C = {B, PrC, PoC}, GA = #graph_area{y = Y0, height = H})  ->
    GyZero  = trunc(Y0 + H),
    egd:filledRectangle(Im, {X1, GyZero}, {X2, Yproc1}, PrC),
    egd:filledRectangle(Im, {X1, Yproc1}, {X2, Yport1}, PoC),
    egd:line(Im, {X1, Yport1}, {X2, Yport1}, B), % top line
    egd:line(Im, {X1, Yport2}, {X1, Yport1}, B), % right line
    egd:line(Im, {X2, Yport1}, {X2, Yport2}, B), % right line
    draw_graf(Im, [{X2, Yproc2, Yport2}|Data], C, GA);

draw_graf(Im, [{X1, Ys1 = [{Yproc1,Yport1}|_]}, {X2, Yproc2, Yport2}|Data], C = {B, PrC, PoC}, GA = #graph_area{y = Y0, height = H})  ->
    GyZero  = trunc(Y0 + H),
    Yprocs = [Yp || {Yp, _} <- Ys1],
    Yports = [Yp || {_, Yp} <- Ys1],

    YprMin = lists:min(Yprocs),
    YprMax = lists:max(Yprocs),
    YpoMax = lists:max(Yports),
    egd:filledRectangle(Im, {X1, GyZero}, {X2, Yproc1}, PrC),
    egd:filledRectangle(Im, {X1, Yproc1}, {X2, Yport1}, PoC),
    egd:filledRectangle(Im, {X1, Yport1}, {X2, Yport1}, B), % top line
    egd:filledRectangle(Im, {X2, Yport1}, {X2, Yport2}, B), % right line

    egd:filledRectangle(Im, {X1, GyZero}, {X1, YprMin}, PrC), % left proc green line
    egd:filledRectangle(Im, {X1, YprMax}, {X1, YpoMax}, PoC), % left port line
    egd:filledRectangle(Im, {X1, YprMax}, {X1, YprMin}, B),
     
    draw_graf(Im, [{X2, Yproc2, Yport2}|Data], C, GA);

draw_graf(Im, [{X1, Ys1 = [{Yproc1,Yport1}|_]}], {B, PrC, PoC}, _GA = #graph_area{y = Y0, width=Width, height = H})  ->
    GyZero  = trunc(Y0 + H),
    Yprocs = [Yp || {Yp, _} <- Ys1],
    Yports = [Yp || {_, Yp} <- Ys1],

    YprMin = lists:min(Yprocs),
    YprMax = lists:max(Yprocs),
    YpoMax = lists:max(Yports),
    egd:filledRectangle(Im, {X1, GyZero}, {Width, Yproc1}, PrC),
    egd:filledRectangle(Im, {X1, Yproc1}, {Width, Yport1}, PoC),
    egd:filledRectangle(Im, {X1, Yport1}, {Width, Yport1}, B), % top line
    egd:filledRectangle(Im, {X1, GyZero}, {X1, YprMin}, PrC), % left proc green line
    egd:filledRectangle(Im, {X1, YprMax}, {X1, YpoMax}, PoC), % left port line
    egd:filledRectangle(Im, {X1, YprMax}, {X1, YprMin}, B),
    ok;
draw_graf(_, _, _, _) -> 
    ok.

draw_xticks(Image, Color, XticksArea, {Xmin, Xmax}, Data) ->
    #graph_area{x = X0, y = Y0, width = Width} = XticksArea,
    
    DX = Width/(Xmax - Xmin),
    Offset = X0 - Xmin*DX, 
    Y = trunc(Y0),
    Font = get_font(),
    {FontW, _FontH} = egd_font:size(Font),
    egd:filledRectangle(Image, {trunc(X0), Y}, {trunc(X0 + Width), Y}, Color), 
    lists:foldl(
    	fun ({X,_,_}, PX) ->
	    X1 = trunc(Offset + X*DX),
	    
	    % Optimization:
	    % if offset has past half the previous text
	    % start checking this text
	    
	    if 
	    	X1 > PX ->
		    Text = lists:flatten(io_lib:format("~.3f", [float(X)])),
		    TextLength = length(Text),
		    TextWidth = TextLength*FontW,
		    Spacing = 2,
		    if 
		    	X1 > PX + round(TextWidth/2) + Spacing ->
		    	    egd:line(Image, {X1, Y - 3}, {X1, Y + 3}, Color),
		    	    text(Image, {X1 - round(TextWidth/2), Y + 2}, Font, Text, Color),
			    X1 + round(TextWidth/2) + Spacing;
			true ->
			    PX
		    end;
		true ->
		    PX
	    end
	end, 0, Data).

draw_yticks(Im, Color, TickArea, {_,Ymax}, HOffset) ->
    #graph_area{x = X0, y = Y0, width = Width, height = Height} = TickArea,
    Font = get_font(),
    X = trunc(X0 + Width),
    Dy = (Height)/(Ymax),
    Yts = if 
	Height/(Ymax*12) < 1.0 -> round(1 + Ymax*15/Height);
	true -> 1
    end,
    egd:filledRectangle(Im, {X, trunc(0 + Y0)}, {X, trunc(Y0 + Height)}, Color),
    draw_yticks0(Im, Font, Color, 0, Yts, Ymax, {X, Height, Dy}, HOffset).

draw_yticks0(Im, Font, Color, Yi, Yts, Ymax, Area, HOffset) when Yi =< Ymax -> 
    {X, Height, Dy} = Area, 
    Y = round(Height - (Yi*Dy) + 3),

    egd:filledRectangle(Im, {X - 3, Y}, {X + 3, Y}, Color), 
    Text = lists:flatten(io_lib:format("~p", [Yi])),
    text(Im, {HOffset, Y - 4}, Font, Text, Color),
    draw_yticks0(Im, Font, Color, Yi + Yts, Yts, Ymax, Area, HOffset);
draw_yticks0(_, _, _, _, _, _, _,_) -> ok.

%%% -------------------------------------
%%% ACTIVITIES
%%% -------------------------------------

%% activities(Width, Height, Range, Activities) -> Binary
%% In:
%%	Width = integer()
%%	Height = integer()
%%	Range = {float(), float()}
%%	Activities = [{float(), active | inactive}]
%% Out:
%%	Binary = binary()

activities(Width, Height, {UXmin, UXmax}, Activities) ->
    {Xmin, Xmax} = case Activities of 
                       [] -> {0.0, 0.0};
                       _ ->{element(1, hd(Activities)),
                            element(1, lists:last(Activities))}
                   end,
    activities0(Width, Height, {lists:min([Xmin, UXmin]), 
                                lists:max([UXmax, Xmax])}, Activities).

activities(Width, Height, Activities) ->
    {Xmin, _, _} = hd(Activities),
    {Xmax, _, _} = lists:last(Activities),
    activities0(Width, Height, {Xmin, Xmax}, Activities).

activities0(Width, Height, {Xmin, Xmax}, Activities) ->
    Image = egd:create(Width, Height),
    Grey = egd:color(Image, {200, 200, 200}),
    HO = 10,
    ActivityArea = #graph_area{x = HO, y = 0, width = Width - 2*HO, height = Height},
    egd:filledRectangle(Image, {0, 0}, {Width, Height}, Grey),
    draw_activity(Image, {Xmin, Xmax}, ActivityArea, Activities),
    Binary = egd:render(Image, png),
    egd:destroy(Image),
    Binary.

draw_activity(Image, {Xmin, Xmax}, Area = #graph_area{width = Width}, Acts) ->
    White = egd:color({255, 255, 255}),
    Green = egd:color({0,250, 0}),
    Black = egd:color({0, 0, 0}),
    Orange = egd:color({255, 165, 0}),
    Dx    = Width/(Xmax - Xmin),
    draw_activity(Image, {Xmin, Xmax}, Area, {White, Green, Black, Orange}, Dx, Acts).

draw_activity(_, _, _, _, _, []) -> ok;  
draw_activity(Image, {Xmin, Xmax}, _Area = #graph_area{ height = Height, x = X0 }, {_Cw, Cg, _Cb, Co}, Dx, 
              [{Xa1, active, InOutXas1}]) ->
    draw_in_out_activities(Image, Xmin,  X0, Height, {Cg, Co}, 
                           Dx, Xa1, Xmax, {{X0, 0}, {X0, Height-1}}, InOutXas1);
draw_activity(_, _, _, _, _, [_])-> ok;
draw_activity(Image, {Xmin, Xmax}, Area = #graph_area{ height = Height, x = X0 }, {Cw, Cg, Cb,Co}, Dx, 
              [{Xa1, State, InOutXas1}, {Xa2, Act2, InOutXas2} | Acts]) ->
    X1 = erlang:trunc(X0 + Dx*Xa1 - Xmin*Dx),
    X2 = erlang:trunc(X0 + Dx*Xa2 - Xmin*Dx),
    if X1 < X2 ->
            case State of
                inactive ->
                    egd:filledRectangle(Image, {X1, 0}, {X2, Height - 1}, Cw),
                    egd:rectangle(Image, {X1, 0}, {X2, Height - 1}, Cb),
                    draw_activity(Image, {Xmin, Xmax}, Area, {Cw, Cg, Cb, Co}, 
                                  Dx, [{Xa2, Act2, InOutXas2} | Acts]);
                active ->
                    draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co},
                                           Dx, Xa1, Xa2, {{X0, 0}, {X0, Height-1}}, InOutXas1),
                    draw_activity(Image, {Xmin, Xmax}, Area, {Cw, Cg, Cb, Co}, 
                                  Dx, [{Xa2, Act2, InOutXas2} | Acts])
            end;
       true ->
            draw_activity(Image, {Xmin, Xmax}, Area, {Cw, Cg, Cb, Co}, 
                          Dx, [{Xa2, Act2, InOutXas2} | Acts])
    end.
  
draw_in_out_activities(Image, Xmin, X0, Height, {Cg, _Co}, Dx, Xa1, Xa2, _PrevPts, []) ->
    X1 = erlang:trunc(X0 + Dx*Xa1 - Xmin*Dx),
    X2 = erlang:trunc(X0 + Dx*Xa2 - Xmin*Dx),
    if  X1 < X2 ->
            egd:filledRectangle(Image, {X1, 0}, {X2, Height - 1}, Cg);
        true -> ok
    end;
draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co}, Dx, Xa1, Xa2, PrevPts, [{in, Xa}|Acts]) ->
    X1 = erlang:trunc(X0 + Dx*Xa1 - Xmin*Dx),
    X2 = erlang:trunc(X0 + Dx*Xa - Xmin*Dx),
    P1 = {X1, 0}, 
    P2 = {X2, Height-1},
    case {P1, P2} == PrevPts of 
        true -> 
            draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co}, Dx, Xa, Xa2, PrevPts, Acts);
        false ->
            egd:filledRectangle(Image, P1, P2, Co),
            draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co}, Dx, Xa, Xa2, {P1, P2}, Acts)
    end;
draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co}, Dx, Xa1, Xa2, PrevPts, [{out, Xa}|Acts]) ->
    X1 = erlang:trunc(X0 + Dx*Xa1 - Xmin*Dx),
    X2 = erlang:trunc(X0 + Dx*Xa - Xmin*Dx),
    P1 = {X1, 0},
    P2 = {X2, Height-1},
    case {P1, P2} == PrevPts of 
        true -> 
            draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co}, Dx, Xa, Xa2, PrevPts, Acts);
        false ->
            egd:filledRectangle(Image, {X1, 0}, {X2, Height - 1}, Cg),
            draw_in_out_activities(Image, Xmin, X0, Height, {Cg, Co}, Dx, Xa, Xa2, {P1, P2}, Acts)
    end.
    
    

%%% -------------------------------------
%%% Process lifetime
%%% Used by processes page
%%% -------------------------------------

proc_lifetime(Width, Height, Start, End, ProfileTime) ->
    Im = egd:create(round(Width), round(Height)),
    Black = egd:color(Im, {0, 0, 0}),
    Green = egd:color(Im, {0, 255, 0}),
    Grey = egd:color(Im, {128, 128, 128}),
    % Ratio and coordinates

    DX = (Width-1)/ProfileTime,
    X1 = round(DX*Start),
    X2 = round(DX*End),
                                                
    % Paint
    egd:rectangle(Im, {0,0}, {Width-1, Height-1}, Grey),
    egd:filledRectangle(Im, {X1, 0}, {X2, Height - 1}, Green),
    egd:rectangle(Im, {X1, 0}, {X2, Height - 1}, Black),

    Binary = egd:render(Im, png),
    egd:destroy(Im),
    Binary.

%%% -------------------------------------
%%% Percentage
%%% Used by process_info page
%%% Percentage should be 0.0 -> 1.0
%%% -------------------------------------
percentage(Width, Height, Percentage) ->
    Font = get_font(),
    Im = egd:create(round(Width), round(Height)),
    Black = egd:color(Im, {0, 0, 0}),
    Orange = egd:color(Im, {255, 165, 0}),

    % Ratio and coordinates

    X = round(Width - 1 - Percentage*(Width - 1)),

    % Paint
    egd:filledRectangle(Im, {X, 0}, {Width - 1, Height - 1}, Orange),
    {FontW, _} = egd_font:size(Font), 
    String = lists:flatten(io_lib:format("~.10B %", [round(100*Percentage)])),

    text(	Im, 
		{round(Width/2 - (FontW*length(String)/2)), 0}, 
    		Font,
		String,
		Black),
    egd:rectangle(Im, {X, 0}, {Width - 1, Height - 1}, Black),
    
    Binary = egd:render(Im, png),
    egd:destroy(Im),
    Binary.


calltime_percentage(Width, Height, CallTime, Percentage) ->
    Im = egd:create(round(Width), round(Height)),
    Font = get_font(),
    Black = egd:color(Im, {0, 0, 0}),
    Green = egd:color(Im, {0, 255, 0}),
    Grey = egd:color(Im, {128, 128, 128}),
    % Ratio and coordinates
    X = round(Percentage*(Width - 1)),
    egd:filledRectangle(Im, {0,0}, {Width-1, Height-1}, Grey),
    egd:filledRectangle(Im, {0, 0}, {X-1, Height - 1}, Green),
    {FontW, _} = egd_font:size(Font), 
    String = lists:flatten(io_lib:format("~.3f      ~.10B%",
                                         [float(CallTime), round(100*Percentage)])),
    text(	Im, 
		{round(Width/2 - (FontW*length(String)/2)), 0}, 
    		Font,
		String,
		Black),
    egd:rectangle(Im, {0, 0}, {X-1, Height - 1}, Black),
    
    Binary = egd:render(Im, png),
    egd:destroy(Im),
    Binary.


get_font() ->
    case ets:info(egd_font_table) of 
        undefined ->
            Filename = filename:join([code:priv_dir(percept2),"fonts", "6x11_latin1.wingsfont"]),
            egd_font:load(Filename),
            {Font, _} =ets:first(egd_font_table),
            Font;
        _ ->
            {Font, _} =ets:first(egd_font_table),
            Font
    end.
   
text(Image, {X,Y}, Font, Text, Color) ->
    egd:text(Image, {X,Y-2}, Font, Text, Color).


query_fun_time(Width, Height, {QueryStart, FunStart}, {QueryEnd, FunEnd}) ->
    Im = egd:create(round(Width), round(Height)),
%%    Black =  egd:color(Im, {0, 0, 0}),
    Green = egd:color(Im, {0, 255, 0}),
    PaleGreen = egd:color(Im, {143,188,143}),
    Grey = egd:color(Im, {128, 128, 128}),
    % Ratio and coordinates
    Start = lists:min([QueryStart, FunStart]),
    End = lists:max([QueryEnd,FunEnd]),
    TimePeriod= End-Start,
    DX = (Width-1)/TimePeriod,
    X1 = round(DX*(QueryStart-Start)),
    X2 = round(DX*(QueryEnd-Start)),
    X3 = round(DX*(FunStart-Start)),
    X4 = round(DX*(FunEnd-Start)),
    if QueryStart > FunStart andalso QueryEnd < FunEnd -> 
             egd:filledRectangle(Im, {0, 0}, {Width - 1, Height - 1}, Green),
             egd:filledRectangle(Im, {X1, 0}, {X2, Height - 1}, PaleGreen);
       QueryStart =< FunStart andalso QueryEnd >= FunEnd ->
            egd:filledRectangle(Im, {0, 0}, {X2, Height - 1}, Grey),
            egd:filledRectangle(Im, {X3, 0}, {X4, Height - 1}, Green);
       QueryStart =<FunStart andalso QueryEnd <FunEnd ->
            egd:filledRectangle(Im, {0, 0}, {X3, Height - 1}, Grey),
            egd:filledRectangle(Im, {X3, 0}, {X2, Height - 1}, PaleGreen),
            egd:filledRectangle(Im, {X2, 0}, {X4, Height - 1}, Green);
       QueryStart >FunStart andalso QueryEnd >= FunEnd ->
            egd:filledRectangle(Im, {0, 0}, {X1, Height - 1}, Green),
            egd:filledRectangle(Im, {X1, 0}, {X4, Height - 1}, PaleGreen),
            egd:filledRectangle(Im, {X4, 0}, {X2, Height - 1}, Grey);
       true ->
            io:format("Unhandled case in percept_image:query_fun_time.\n")
    end,
    Binary = egd:render(Im, png),
    egd:destroy(Im),
    Binary.

inter_node_message_image(Width, Height, _, _, []) ->
    error_graph(Width, Height,"No message communication data recorded.");
inter_node_message_image(Width, Height, Xmin, Xmax, Data) ->
    Ymin = 0, 
    Ymax = case Data of
               [] -> 0;
               _ -> lists:max(element(2,lists:unzip3(Data)))
            end,
        % Calculate areas
    HO = 20,
    GrafArea   = #graph_area{x = HO, y = 4, width = Width - 2*HO, height = Height - 17},
    XticksArea = #graph_area{x = HO, y = Height - 13, width = Width - 2*HO, height = 13},
    YticksArea = #graph_area{x = 1,  y = 4, width = HO, height = Height - 17},
    
    %% Initiate Image
    Image = egd:create(Width, Height),
    Black = egd:color(Image, {0, 0, 0}),
    Red = egd:color(Image, {255, 0, 0}),
    draw_cross_graf(Image, Data, {Red, Red}, GrafArea, {Xmin, Ymin, Xmax, Ymax}),
    draw_xticks(Image, Black, XticksArea, {Xmin, Xmax}, Data),
    draw_yticks(Image, Black, YticksArea, {Ymin, Ymax},0),
    Binary = egd:render(Image, png),
    egd:destroy(Image),
    Binary.

draw_cross_graf(Im, Data, Colors, GA = #graph_area{x = X0, y = Y0, width = Width, height = Height},
                {Xmin, _Ymin, Xmax, Ymax}) ->
    Dx = (Width)/(Xmax - Xmin),
    Dy = (Height)/(Ymax),
    Plotdata = [{trunc(X0 + X*Dx - Xmin*Dx), trunc(Y0 + Height - Y1*Dy)} 
                || {X, Y1, _} <- Data],
    draw_cross_graf1(Im, Plotdata, Colors, GA).

draw_cross_graf1(Im, [{X1, Y1}|Data], C={B, _}, GA) ->
    egd:line(Im, {X1-3, Y1}, {X1+2, Y1}, B),
    egd:line(Im, {X1, Y1-3}, {X1, Y1+2}, B),  
    draw_cross_graf1(Im, Data, C, GA);
draw_cross_graf1(_Im, [], _, _) -> ok.

%% @spec minmax([{X, Y}]) -> {MinX, MinY, MaxX, MaxY}
%%	X = number()
%%	Y = number()
%%	MinX = number()
%%	MinY = number()
%%	MaxX = number()
%%	MaxY = number()
%% @doc Returns the min and max of a set of 2-dimensional numbers.
minmax(Data) ->
    Xs = [ X || {X,_Y} <- Data],
    Ys = [ Y || {_X, Y} <- Data],
    {lists:min(Xs), lists:min(Ys), lists:max(Xs), lists:max(Ys)}.

%% NOT for general-purpose.
remove_duplicates([]) ->
    [];
remove_duplicates([X|Tl]) ->
    remove_duplicates(Tl, X, []).

remove_duplicates([], Last, Acc) ->
    lists:reverse([Last|Acc]);
remove_duplicates([X], Last, Acc) ->
    lists:reverse([X, Last|Acc]);
remove_duplicates([X={X1, Y1, Y2}|Tl], Last={LastX1, LastY1, LastY2}, Acc) ->
    if X1==LastX1 ->
            MinY1=lists:min([Y1, LastY1]), 
            MinY2=lists:min([Y2, LastY2]),
            remove_duplicates(Tl, {LastX1, MinY1, MinY2}, Acc);
       true ->
            remove_duplicates(Tl, X, [Last|Acc])
    end.
