%  Copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%
%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.
%%%-------------------------------------------------------------------
%% Author: christian hennig <hennig@zib.de>
%% Created: Feb 11, 2009
%% Description: TODO: Add description to metric
-module(metric).

%%
%% Include files
%%

%%
%% Exported Functions
%%
-export([ring_health/0]).

%%
%% API Functions
%%

ring_health() ->
    RealRing = statistics:get_ring_details(),
    Ring = lists:filter(fun (X) -> is_valid(X) end, RealRing),
    RingSize = length(Ring),
    case RingSize>1 of 
        true ->
			ListsErrors = lists:map(fun (Node_Details) -> node_health(Node_Details,Ring) end, Ring),
    		{lists:foldr(fun (X,Acc) -> X+Acc end, 0, ListsErrors)/length(ListsErrors),RingSize};
        false ->
            {1,RingSize}
    end.





node_health({ok, Details},Ring) ->
	Node = node_details:me(Details),
	MyIndex = get_indexed_id(Node, Ring),
    NIndex = length(Ring),
	PredList = node_details:predlist(Details),
    Node = node_details:me(Details),
    SuccList = node_details:succlist(Details),
	
    PredIndices = lists:map(fun(Pred) -> get_indexed_pred_id(Pred, Ring, MyIndex, NIndex) end, PredList),
    SuccIndices = lists:map(fun(Succ) -> get_indexed_succ_id(Succ, Ring, MyIndex, NIndex) end, SuccList),
    
    NP= util:min(NIndex-1,config:read(pred_list_length)),
    NS= util:min(NIndex-1,config:read(pred_list_length)),
    
    Ps = lists:sublist(PredIndices++lists:duplicate(NP, -1*(NIndex-1)),NP),
    Ss = lists:sublist(SuccIndices++lists:duplicate(NS, (NIndex-1)),NS),
    
    CorrectFakP= 1/(NIndex*lists:foldr(fun (A,Acc) -> 1/A+Acc end, 0, lists:seq(1, NP))), 
    CorrectFakS= 1/(NIndex*lists:foldr(fun (A,Acc) -> 1/A+Acc end, 0, lists:seq(1, NS))),
    NormPs = norm(Ps,1), 
    NormSs = norm(Ss,1),
	
    
    P = fun(A, AccIn) -> A + AccIn end,
    Error = (lists:foldr( P , 0, NormPs)*CorrectFakP+lists:foldr( P , 0, NormSs)*CorrectFakS)/2,
    %io:format("~p~n",[{NormPs,NormSs}]),
    Error;
node_health(failed,_Ring) ->
    0.

norm([],_) ->
    [];
norm([H|T],X) ->
    [(erlang:abs(H)-X)*(1/X)|norm(T,X+1)].


is_valid({ok, _}) ->
    true;
is_valid({failed}) ->
    false.

get_id(Node) ->
    case node:is_null(Node) of
		true ->
			"null";
		false ->
	    	node:id(Node)
    end.

get_indexed_pred_id(Node, Ring, MyIndex, NIndex) ->
    case get_indexed_id(Node, Ring) of
        "null" -> "null";
        "none" -> "none";
        Index -> ((Index-MyIndex+NIndex) rem NIndex)-NIndex
    end.

get_indexed_succ_id(Node, Ring, MyIndex, NIndex) ->
    case get_indexed_id(Node, Ring) of
        "null" -> "null";
        "none" -> "none";
        Index -> (Index-MyIndex+NIndex) rem NIndex
    end.

get_indexed_id(Node, Ring) ->
    case node:is_null(Node) of
        true -> "null";
        false -> get_indexed_id(Node, Ring, 0)
    end.

get_indexed_id(Node, [{ok, Details}|Ring], Index) ->
    case node:id(Node) =:= node:id(node_details:me(Details)) of
        true -> Index;
        false -> get_indexed_id(Node, Ring, Index+1)
    end;

get_indexed_id(_Node, [], _Index) ->
   "none".
    
    

%%
%% Local Functions
%%

