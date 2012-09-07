% @copyright 2009-2012 Zuse Institute Berlin

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

% @author Florian Schintke <schintke@zib.de>
% @doc operations on the end user transaction log
% @version $Id$
-module(tx_tlog).
-author('schintke@zib.de').
-vsn('$Id$').

-include("scalaris.hrl").
-include("client_types.hrl").

%% Operations on TLogs
-export([empty/0]).
-export([add_entry/2]).
-export([add_or_update_status_by_key/3]).
-export([update_entry/2]).
-export([sort_by_key/1]).
-export([find_entry_by_key/2]).
-export([is_sane_for_commit/1]).
-export([get_insane_keys/1]).

%% Operations on entries of TLogs
-export([new_entry/5]).
-export([get_entry_operation/1, set_entry_operation/2]).
-export([get_entry_key/1,       set_entry_key/2]).
-export([get_entry_status/1,    set_entry_status/2]).
-export([get_entry_value/1,     set_entry_value/2]).
-export([drop_value/1]).
-export([get_entry_version/1]).

-ifdef(with_export_type_support).
-export_type([tlog/0, tlog_entry/0]).
-export_type([tx_status/0]).
-export_type([tx_op/0]).
-endif.

-type tx_status() :: ?value | {fail, abort | not_found}.
-type tx_op()     :: ?read | ?write.

-type tlog_key() :: client_key(). %%| ?RT:key().
%% TLogEntry: {Operation, Key, Status, Value, Version}
%% Sample: {?read,"key3",?value,"value3",0}
-type tlog_entry() ::
          { tx_op(),                  %% operation
            tlog_key(),             %% key
            non_neg_integer() | -1,   %% version
            tx_status(),              %% status
            any()                     %% value
          }.
-type tlog() :: [tlog_entry()].

% @doc create an empty list
-spec empty() -> tlog().
empty() -> [].

-spec add_entry(tlog(), tlog_entry()) -> tlog().
add_entry(TransLog, Entry) -> [ Entry | TransLog ].

-spec add_or_update_status_by_key(tlog(), tlog_key(), tx_status()) -> tlog().
add_or_update_status_by_key([], Key, Status) ->
    [new_entry(?write, Key, _Vers = 0, Status, _Val = 0)];
add_or_update_status_by_key([Entry | T], Key, Status)
  when element(2, Entry) =:= Key ->
    [set_entry_status(Entry, Status) | T];
add_or_update_status_by_key([Entry | T], Key, Status) ->
    [Entry | add_or_update_status_by_key(T, Key, Status)].

-spec update_entry(tlog(), tlog_entry()) -> tlog().
update_entry(TLog, Entry) ->
    lists:keyreplace(get_entry_key(Entry), 2, TLog, Entry).

-spec sort_by_key(tlog()) -> tlog().
sort_by_key(TLog) -> lists:keysort(2, TLog).

-spec find_entry_by_key(tlog(), tlog_key()) -> tlog_entry() | false.
find_entry_by_key(TLog, Key) ->
    lists:keyfind(Key, 2, TLog).

-spec entry_is_sane_for_commit(tlog_entry(), boolean()) -> boolean().
entry_is_sane_for_commit(Entry, Acc) ->
    Acc andalso
        not (is_tuple(get_entry_status(Entry))
             andalso fail =:= element(1, get_entry_status(Entry))
             andalso not_found =/= element(2, get_entry_status(Entry))
            ).

-spec is_sane_for_commit(tlog()) -> boolean().
is_sane_for_commit(TLog) ->
    lists:foldl(fun entry_is_sane_for_commit/2, true, TLog).

-spec get_insane_keys(tlog()) -> [client_key()].
get_insane_keys(TLog) ->
    lists:foldl(fun(X, Acc) ->
                        case entry_is_sane_for_commit(X, true) of
                            true -> Acc;
                            false -> [get_entry_key(X) | Acc]
                        end
                end, [], TLog).

%% Operations on Elements of TransLogs (public)
-spec new_entry(tx_op(), client_key() | ?RT:key(),
                non_neg_integer() | -1,
                tx_status(), any()) -> tlog_entry().
new_entry(Op, Key, Vers, Status, Val) ->
    {Op, Key, Vers, Status, Val}.

-spec get_entry_operation(tlog_entry()) -> tx_op().
get_entry_operation(Element) -> element(1, Element).

-spec set_entry_operation(tlog_entry(), tx_op()) -> tlog_entry().
set_entry_operation(Element, Val) -> setelement(1, Element, Val).

-spec get_entry_key(tlog_entry()) -> client_key() | ?RT:key().
get_entry_key(Element)       -> element(2, Element).

-spec set_entry_key(tlog_entry(), client_key() | ?RT:key()) -> tlog_entry().
set_entry_key(Entry, Val)    -> setelement(2, Entry, Val).

-spec get_entry_version(tlog_entry()) -> non_neg_integer() | -1.
get_entry_version(Element)   -> element(3, Element).

-spec get_entry_status(tlog_entry()) -> tx_status().
get_entry_status(Element)    -> element(4, Element).

-spec set_entry_status(tlog_entry(), tx_status()) -> tlog_entry().
set_entry_status(Element, Val) -> setelement(4, Element, Val).

-spec get_entry_value(tlog_entry()) -> any().
get_entry_value(Element)     -> element(5, Element).

-spec set_entry_value(tlog_entry(), any()) -> tlog_entry().
set_entry_value(Element, Val)     -> setelement(5, Element, Val).

-spec drop_value(tlog_entry()) -> tlog_entry().
drop_value(Element)     -> setelement(5, Element, ?value_dropped).
