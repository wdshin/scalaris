% @copyright 2011 Zuse Institute Berlin

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

%% @author Maik Lange <malange@informatik.hu-berlin.de>
%% @doc    Bloom Filter implementation
%% @end
%% @reference A. Broder, M. Mitzenmacher 
%%          <em>Network Applications of Bloom Filters: A Survey</em> 
%%          2004 Internet Mathematics 1(4) 
%% @version $Id$

-module(bloom).

-include("record_helpers.hrl").

-behaviour(bloom_beh).

-include("scalaris.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Types
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-record(bloom, {
                size          = 0                             :: non_neg_integer(),%bit-length of the bloom filter - requirement: size rem 8 = 0
                filter        = <<>>                          :: binary(),         %length = size div 8
                target_fpr    = ?required(bloom, target_fpr)  :: float(),          %target false-positive-rate
                hfs           = ?required(bloom, hfs)         :: ?REP_HFS:hfs(),   %HashFunctionSet
                max_items     = ?required(bloom, max_items)   :: non_neg_integer(),%extected number of items
                items_count   = 0                             :: non_neg_integer() %number of inserted items
               }).
-type bloom_filter_t() :: #bloom{}.

-include("bloom_beh.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% API  
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc creates a new bloom filter
new_(N, FPR, Hfs) ->
    Size = resize(calc_least_size(N, FPR), 8), %BF bit size should fit into a number of bytes
    #bloom{
           size = Size,
           filter = <<0:Size>>,
           max_items = N, 
           target_fpr = calc_FPR(Size, N, calc_HF_num(Size, N)),
           hfs = Hfs,
           items_count = 0
          }.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc adds a range of items to bloom filter
add_list_(Bloom, Items) ->
    #bloom{
           size = BFSize, 
           hfs = Hfs, 
           items_count = FilledCount,
           filter = Filter
          } = Bloom,
    Pos = lists:append([apply(element(1, Hfs), apply_val, [Hfs, Item]) || Item <- Items]), %TODO: USE FLATTEN???
    Positions = lists:map(fun(X) -> X rem BFSize end, Pos),
    Bloom#bloom{
                filter = set_Bits(Filter, Positions),
                items_count = FilledCount + length(Items)
               }.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc returns true if the bloom filter contains item
is_element_(Bloom, Item) -> 
    #bloom{
           size = BFSize,		   
           hfs = Hfs, 
           filter = Filter
          } = Bloom,
    Pos = apply(element(1, Hfs), apply_val, [Hfs, Item]), 
    Positions = lists:map(fun(X) -> X rem BFSize end, Pos),
    check_Bits(Filter, Positions).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc joins two bloom filter, returned bloom filter represents their union
join_(#bloom{size = Size1, max_items = ExpItem1, items_count = Items1, 
             target_fpr = Fpr1, filter = F1, hfs = Hfs}, 
      #bloom{size = Size2, max_items = ExpItem2, items_count = Items2, 
             target_fpr = Fpr2, filter = F2}) ->
    NewSize = erlang:max(Size1, Size2),
    <<F1Val : Size1>> = F1,
    <<F2Val : Size2>> = F2,
    NewFVal = F1Val bor F2Val,
    #bloom{
           size = NewSize,
           filter = <<NewFVal:NewSize>>,                            
           max_items = erlang:max(ExpItem1, ExpItem2), 
           target_fpr = erlang:min(Fpr1, Fpr2),
           hfs = Hfs,                              
           items_count = Items1 + Items2 %approximation            
           }.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc checks equality of two bloom filters
equals_(Bloom1, Bloom2) ->
    #bloom{
           size = Size1, 
           items_count = Items1,
           filter = Filter1
          } = Bloom1,
    #bloom{
           size = Size2, 
           items_count = Items2,
           filter = Filter2
          } = Bloom2,
    Size1 =:= Size2 andalso
        Items1 =:= Items2 andalso
        Filter1 =:= Filter2.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc bloom filter debug information
print_(Bloom) -> 
    #bloom{
           max_items = MaxItems, 
           target_fpr = TargetFpr,
           size = Size,
           hfs = Hfs,
           items_count = NumItems
          } = Bloom,
    HCount = apply(element(1, Hfs), hfs_size, [Hfs]),
    [{filter_bit_size, Size},
     {struct_byte_size, byte_size(term_to_binary(Bloom))},
     {hash_fun_num, HCount},
     {max_items, MaxItems},
     {dest_fpr, TargetFpr},
     {items_inserted, NumItems},
     {act_fpr, calc_FPR(Size, NumItems, HCount)},
     {compression_rate, Size / MaxItems}].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

get_property(Bloom, Property) ->
    FieldNames = record_info(fields, bloom),
    {_, N} = lists:foldl(fun(I, {Nr, Res}) -> case I =:= Property of
                                                  true -> {Nr + 1, Nr};
                                                  false -> {Nr + 1, Res}
                                              end 
                         end, {1, -1}, FieldNames),
    if
        N =:= -1 -> not_found;
        true -> erlang:element(N + 1, Bloom)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% bit operations
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% @doc Sets all filter-bits at given positions to 1
-spec set_Bits(binary(), [integer()]) -> binary().
set_Bits(Filter, []) -> 
    Filter;
set_Bits(Filter, [Pos | Positions]) -> 
    PreByteNum = Pos div 8,
    <<PreBin:PreByteNum/binary, OldByte:8, PostBin/binary>> = Filter,
    NewByte = OldByte bor (1 bsl (Pos rem 8)),
    set_Bits(<<PreBin/binary, NewByte:8, PostBin/binary>>, Positions).

% @doc Checks if all bits are set on a given position list
-spec check_Bits(binary(), [integer()]) -> boolean().
check_Bits(_, []) -> 
    true;
check_Bits(Filter, [Pos | Positions]) -> 
    PreBytes = Pos div 8,
    <<_:PreBytes/binary, CheckByte:8, _/binary>> = Filter,
    case 0 =/= CheckByte band (1 bsl (Pos rem 8)) of
        true -> check_Bits(Filter, Positions);
        false -> false
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% helper functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec ln(X::number()) -> float().
ln(X) -> 
    util:log(X, math:exp(1)).

% @doc Increases Val until Val rem Div == 0.
-spec resize(integer(), integer()) -> integer().
resize(Val, Div) when Val rem Div == 0 -> 
    Val;
resize(Val, Div) when Val rem Div /= 0 -> 
    resize(Val + 1, Div).
