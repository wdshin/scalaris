% @copyright 2008-2011 Zuse Institute Berlin

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

%%% @author Thorsten Schuett <schuett@zib.de>
%%% @doc    Unit tests for database implementations. Define the TEST_DB macro
%%          to set the database module that is being tested.
%%% @end
%% @version $Id$

-include("scalaris.hrl").
-include("unittest.hrl").

tests_avail() ->
    [read, write,
     delete, get_load_and_middle, split_data, update_entries,
     changed_keys, various_tests,
     % random tester functions:
     tester_new, tester_set_entry, tester_update_entry,
     tester_delete_entry1, tester_delete_entry2,
     tester_write,
     tester_delete, tester_add_data,
     tester_get_entries2, tester_get_entries3_1, tester_get_entries3_2,
     tester_get_load2,
     tester_split_data, tester_update_entries,
     tester_delete_entries1, tester_delete_entries2,
     tester_changed_keys_get_entry,
     tester_changed_keys_set_entry,
     tester_changed_keys_update_entry,
     tester_changed_keys_delete_entry,
     tester_changed_keys_read,
     tester_changed_keys_write,
     tester_changed_keys_delete,
     tester_changed_keys_get_entries2,
     tester_changed_keys_get_entries4,
     tester_get_chunk3,
     tester_delete_chunk3,
     tester_changed_keys_update_entries,
     tester_changed_keys_delete_entries1,
     tester_changed_keys_delete_entries2,
     tester_changed_keys_get_load,
     tester_changed_keys_get_load2,
     tester_changed_keys_split_data1,
     tester_changed_keys_split_data2,
     tester_changed_keys_get_data,
     tester_changed_keys_add_data,
     tester_changed_keys_check_db,
     tester_changed_keys_mult_interval,
     tester_stop_record_changes
    ].

suite() -> [ {timetrap, {seconds, 10}} ].

%% @doc Returns the min of Desired and max_rw_tests_per_suite().
%%      Should be used to limit the number of executions of r/w suites.
-spec rw_suite_runs(Desired::pos_integer()) -> pos_integer().
rw_suite_runs(Desired) ->
    erlang:min(Desired, max_rw_tests_per_suite()).

init_per_suite(Config) ->
    Config2 = unittest_helper:init_per_suite(Config),
    Config3 = unittest_helper:start_minimal_procs(Config2, [], false),
    tester:register_type_checker({typedef, intervals, interval}, intervals, is_well_formed),
    tester:register_value_creator({typedef, intervals, interval}, intervals, tester_create_interval, 1),
    Config3.

end_per_suite(Config) ->
    tester:unregister_type_checker({typedef, intervals, interval}),
    tester:unregister_value_creator({typedef, intervals, interval}),
    unittest_helper:stop_minimal_procs(Config),
    _ = unittest_helper:end_per_suite(Config),
    ok.

-define(db_equals_pattern(Actual, ExpectedPattern),
        % wrap in function so that the internal variables are out of the calling function's scope
        fun() ->
                case Actual of
                    {DB_EQUALS_PATTERN_DB, ExpectedPattern} -> DB_EQUALS_PATTERN_DB;
                    {DB_EQUALS_PATTERN_DB, Any} ->
                        ct:pal("Failed: Stacktrace ~p~n",
                               [util:get_stacktrace()]),
                        ?ct_fail("~p evaluated to \"~p\" which is "
                               "not the expected ~p",
                               [??Actual, Any, ??ExpectedPattern]),
                        DB_EQUALS_PATTERN_DB
                end
        end()).

read(_Config) ->
    prop_new(?RT:hash_key("Unknown")).

write(_Config) ->
    prop_write(?RT:hash_key("Key1"), "Value1", 1, ?RT:hash_key("Key2")).

delete(_Config) ->
    prop_delete(?RT:hash_key("DeleteKey1"), "Value1", false, 0, 1, ?RT:hash_key("DeleteKey2")),
    prop_delete(?RT:hash_key("DeleteKey1"), "Value1", false, 1, 1, ?RT:hash_key("DeleteKey2")).

get_load_and_middle(_Config) ->
    DB = ?TEST_DB:new(),
    ?equals(?TEST_DB:get_load(DB), 0),
    DB2 = ?TEST_DB:write(DB, "Key1", "Value1", 1),
    ?equals(?TEST_DB:get_load(DB2), 1),
    DB3 = ?TEST_DB:write(DB2, "Key1", "Value1", 2),
    ?equals(?TEST_DB:get_load(DB3), 1),
    DB4 = ?TEST_DB:write(DB3, "Key2", "Value2", 1),
    ?equals(?TEST_DB:get_load(DB4), 2),
    DB5 = ?TEST_DB:write(DB4, "Key3", "Value3", 1),
    DB6 = ?TEST_DB:write(DB5, "Key4", "Value4", 1),
    OrigFullList = ?TEST_DB:get_data(DB6),
    {DB7, HisList} = ?TEST_DB:split_data(DB6, node:mk_interval_between_ids("Key2", "Key4")),
    ?equals(?TEST_DB:read(DB7, "Key3"), {ok, "Value3", 1}),
    ?equals(?TEST_DB:read(DB7, "Key4"), {ok, "Value4", 1}),
    ?equals(?TEST_DB:get_load(DB7), 2),
    ?equals(length(HisList), 2),
    ?equals(length(?TEST_DB:get_data(DB7)), 2),
    DB8 = ?TEST_DB:add_data(DB7, HisList),
    % lists could be in arbitrary order -> sort them
    ?equals(lists:sort(OrigFullList), lists:sort(?TEST_DB:get_data(DB8))),
    ?TEST_DB:close(DB8).

%% @doc Some split_data tests using fixed values.
%% @see prop_split_data/2
split_data(_Config) ->
    prop_split_data([db_entry:new(1, "Value1", 1),
                     db_entry:new(2, "Value2", 2)], intervals:empty()),
    prop_split_data([db_entry:new(1, "Value1", 1),
                     db_entry:new(2, "Value2", 2)], intervals:all()),
    prop_split_data([db_entry:new(1, "Value1", 1),
                     db_entry:new(2, "Value2", 2)], intervals:new(2)),
    prop_split_data([db_entry:new(1, "Value1", 1),
                     db_entry:new(2, "Value2", 2)], intervals:new(5)),
    prop_split_data([db_entry:new(1, "Value1", 1),
                     db_entry:new(2, "Value2", 2),
                     db_entry:new(3, "Value3", 3),
                     db_entry:new(4, "Value4", 4),
                     db_entry:new(5, "Value5", 5)],
                    intervals:new('[', 2, 4, ')')),
    prop_split_data([db_entry:new(1, "Value1", 1),
                     db_entry:new(2, "Value2", 2),
                     db_entry:new(3, "Value3", 3),
                     db_entry:new(4, "Value4", 4),
                     db_entry:new(5, "Value5", 5)],
                    intervals:union(intervals:new('[', 1, 3, ')'),
                                    intervals:new(4))),
    prop_split_data([db_entry:set_writelock(db_entry:new(1, "Value1", 1)),
                     db_entry:inc_readlock(db_entry:new(2, "Value2", 2)),
                     db_entry:new(3, "Value3", 3),
                     db_entry:new(4, "Value4", 4),
                     db_entry:new(5, "Value5", 5)],
                    intervals:union(intervals:new('[', 1, 3, ')'),
                                    intervals:new(4))).

%% @doc Some update_entries tests using fixed values.
%% @see prop_update_entries_helper/3
update_entries(_Config) ->
    prop_update_entries_helper([db_entry:new(1, "Value1", 1),
                                db_entry:new(2, "Value2", 1),
                                db_entry:new(3, "Value3", 1),
                                db_entry:new(4, "Value4", 1),
                                db_entry:new(5, "Value5", 1)],
                               [db_entry:new(1, "Value1", 2),
                                db_entry:new(2, "Value2", 2),
                                db_entry:new(3, "Value3", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 2)],
                               [db_entry:new(1, "Value1", 2),
                                db_entry:new(2, "Value2", 2),
                                db_entry:new(3, "Value3", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 2)]),
    prop_update_entries_helper([db_entry:new(1, "Value1", 1),
                                db_entry:new(2, "Value2", 1),
                                db_entry:new(3, "Value3", 1),
                                db_entry:new(4, "Value4", 1),
                                db_entry:new(5, "Value5", 1)],
                               [db_entry:new(1, "Value1", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 3)],
                               [db_entry:new(1, "Value1", 2),
                                db_entry:new(2, "Value2", 1),
                                db_entry:new(3, "Value3", 1),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 3)]),
    prop_update_entries_helper([db_entry:new(1, "Value1", 2),
                                db_entry:new(2, "Value2", 2),
                                db_entry:new(3, "Value3", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 2)],
                               [db_entry:new(1, "Value1", 1),
                                db_entry:new(4, "Value4", 1),
                                db_entry:new(5, "Value5", 1)],
                               [db_entry:new(1, "Value1", 2),
                                db_entry:new(2, "Value2", 2),
                                db_entry:new(3, "Value3", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 2)]),
    prop_update_entries_helper([db_entry:set_writelock(db_entry:new(1, "Value1", 1)),
                                db_entry:inc_readlock(db_entry:new(2, "Value2", 2)),
                                db_entry:new(3, "Value3", 1),
                                db_entry:new(4, "Value4", 1),
                                db_entry:new(5, "Value5", 1)],
                               [db_entry:new(1, "Value1", 2),
                                db_entry:new(2, "Value2", 2),
                                db_entry:new(3, "Value3", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 2)],
                               [db_entry:set_writelock(db_entry:new(1, "Value1", 1)),
                                db_entry:inc_readlock(db_entry:new(2, "Value2", 2)),
                                db_entry:new(3, "Value3", 2),
                                db_entry:new(4, "Value4", 2),
                                db_entry:new(5, "Value5", 2)]),
    prop_update_entry({239309376718523519117394992299371645018, empty_val, false, 0, -1},
                      <<6>>, false, 7, 4).

changed_keys(_Config) ->
    DB = ?TEST_DB:new(),
    
    ?equals(?TEST_DB:get_changes(DB), {[], []}),
    
    DB2 = ?TEST_DB:stop_record_changes(DB),
    ?equals(?TEST_DB:get_changes(DB2), {[], []}),
    
    DB3 = ?TEST_DB:record_changes(DB2, intervals:empty()),
    ?equals(?TEST_DB:get_changes(DB3), {[], []}),
    
    ?TEST_DB:close(DB3).

%% @doc Tests that previously failed with tester-generated values or otherwise
%%      manually generated test cases.
various_tests(_Config) ->
    prop_changed_keys_split_data2([create_db_entry(3, empty_val, false, 0, -1),
                                   create_db_entry(0, empty_val, false, 0, -1)],
                                 intervals:new('[', 3, minus_infinity,']'),
                                 intervals:new(plus_infinity)).

% tester-based functions below:

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:new/0, ?TEST_DB getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_new(Key::?RT:key()) -> true.
prop_new(Key) ->
    DB = ?TEST_DB:new(),
    check_db(DB, {true, []}, 0, [], "check_db_new_1"),
    ?equals(?TEST_DB:read(DB, Key), {ok, empty_val, -1}),
    check_entry(DB, Key, db_entry:new(Key), {ok, empty_val, -1}, false, "check_entry_new_1"),
    ?TEST_DB:close(DB),
    true.

tester_new(_Config) ->
    tester:test(?MODULE, prop_new, 1, rw_suite_runs(10), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:set_entry/2, ?TEST_DB getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_set_entry(DBEntry::db_entry:entry()) -> true.
prop_set_entry(DBEntry) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:set_entry(DB, DBEntry),
    IsNullEntry = db_entry:is_null(DBEntry),
    check_entry(DB2, db_entry:get_key(DBEntry), DBEntry,
                {ok, db_entry:get_value(DBEntry), db_entry:get_version(DBEntry)},
                not IsNullEntry, "check_entry_set_entry_1"),
    case not db_entry:is_empty(DBEntry) andalso
             not (db_entry:get_writelock(DBEntry) andalso db_entry:get_readlock(DBEntry) > 0) andalso
             db_entry:get_version(DBEntry) >= 0 of
        true -> check_db(DB2, {true, []}, 1, [DBEntry], "check_db_set_entry_0");
        _ when IsNullEntry ->
                check_db(DB2, {true, []}, 0, [], "check_db_set_entry_1");
        _    -> check_db(DB2, {false, [DBEntry]}, 1, [DBEntry], "check_db_set_entry_2")
    end,
    ?TEST_DB:close(DB2),
    true.

tester_set_entry(_Config) ->
    tester:test(?MODULE, prop_set_entry, 1, rw_suite_runs(10), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:update_entry/2, ?TEST_DB getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_update_entry(DBEntry1::db_entry:entry(), Value2::?DB:value(), WriteLock2::boolean(),
                        ReadLock2::0..10, Version2::?DB:version()) -> true.
prop_update_entry(DBEntry1, Value2, WriteLock2, ReadLock2, Version2) ->
    DBEntry2 = create_db_entry(db_entry:get_key(DBEntry1), Value2, WriteLock2, ReadLock2, Version2),
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:set_entry(DB, DBEntry1),
    case db_entry:is_null(DBEntry1) of
        true -> % update not possible
            DB3 = DB2,
            ok; 
        false ->
            DB3 = ?TEST_DB:update_entry(DB2, DBEntry2),
            IsNullEntry = db_entry:is_null(DBEntry2),
            check_entry(DB3, db_entry:get_key(DBEntry2), DBEntry2,
                        {ok, db_entry:get_value(DBEntry2), db_entry:get_version(DBEntry2)},
                        not IsNullEntry, "check_entry_update_entry_1"),
            case not db_entry:is_empty(DBEntry2) andalso
                     not (db_entry:get_writelock(DBEntry2) andalso db_entry:get_readlock(DBEntry2) > 0) andalso
                     db_entry:get_version(DBEntry2) >= 0 of
                true -> check_db(DB3, {true, []}, 1, [DBEntry2], "check_db_update_entry_0");
                _ when IsNullEntry ->
                    check_db(DB3, {true, []}, 0, [], "check_db_update_entry_1");
                _    -> check_db(DB3, {false, [DBEntry2]}, 1, [DBEntry2], "check_db_update_entry_2")
            end
    end,
    ?TEST_DB:close(DB3),
    true.

tester_update_entry(_Config) ->
    tester:test(?MODULE, prop_update_entry, 5, rw_suite_runs(10), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:delete_entry/2, ?TEST_DB getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_delete_entry1(DBEntry1::db_entry:entry()) -> true.
prop_delete_entry1(DBEntry1) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:set_entry(DB, DBEntry1),
    DB3 = ?TEST_DB:delete_entry(DB2, DBEntry1),
    check_entry(DB3, db_entry:get_key(DBEntry1), db_entry:new(db_entry:get_key(DBEntry1)),
                {ok, empty_val, -1}, false, "check_entry_delete_entry1_1"),
    check_db(DB3, {true, []}, 0, [], "check_db_delete_entry1_1"),
    ?TEST_DB:close(DB3),
    true.

-spec prop_delete_entry2(DBEntry1::db_entry:entry(), DBEntry2::db_entry:entry()) -> true.
prop_delete_entry2(DBEntry1, DBEntry2) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:set_entry(DB, DBEntry1),
    % note: DBEntry2 may not be the same
    DB3 = ?TEST_DB:delete_entry(DB2, DBEntry2),
    case db_entry:get_key(DBEntry1) =/= db_entry:get_key(DBEntry2) of
        true ->
            IsNullEntry = db_entry:is_null(DBEntry1),
            check_entry(DB3, db_entry:get_key(DBEntry1), DBEntry1,
                {ok, db_entry:get_value(DBEntry1), db_entry:get_version(DBEntry1)},
                not IsNullEntry, "check_entry_delete_entry2_1"),
            case not db_entry:is_empty(DBEntry1) andalso
                     not (db_entry:get_writelock(DBEntry1) andalso db_entry:get_readlock(DBEntry1) > 0) andalso
                     db_entry:get_version(DBEntry1) >= 0 of
                true -> check_db(DB3, {true, []}, 1, [DBEntry1], "check_db_delete_entry2_1a");
                _ when IsNullEntry ->
                        check_db(DB3, {true, []}, 0, [], "check_db_delete_entry2_1b");
                _    -> check_db(DB3, {false, [DBEntry1]}, 1, [DBEntry1], "check_db_delete_entry2_1c")
            end;
        _    ->
            check_entry(DB3, db_entry:get_key(DBEntry1), db_entry:new(db_entry:get_key(DBEntry1)),
                        {ok, empty_val, -1}, false, "check_entry_delete_entry2_2"),
            check_db(DB3, {true, []}, 0, [], "check_db_delete_entry2_2")
    end,
    ?TEST_DB:close(DB3),
    true.

tester_delete_entry1(_Config) ->
    tester:test(?MODULE, prop_delete_entry1, 1, rw_suite_runs(10), [{threads, 2}]).

tester_delete_entry2(_Config) ->
    tester:test(?MODULE, prop_delete_entry2, 2, rw_suite_runs(10), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:write/2, ?TEST_DB getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_write(Key::?RT:key(), Value::?TEST_DB:value(), Version::?TEST_DB:version(), Key2::?RT:key()) -> true.
prop_write(Key, Value, Version, Key2) ->
    DBEntry = db_entry:new(Key, Value, Version),
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:write(DB, Key, Value, Version),
    check_entry(DB2, Key, DBEntry, {ok, Value, Version}, true, "check_entry_write_1"),
    check_db(DB2, {true, []}, 1, [DBEntry], "check_db_write_1"),
    case Key =/= Key2 of
        true -> check_entry(DB2, Key2, db_entry:new(Key2), {ok, empty_val, -1}, false, "write_2");
        _    -> ok
    end,
    ?TEST_DB:close(DB2),
    true.

tester_write(_Config) ->
    tester:test(?MODULE, prop_write, 4, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:delete/2, also validate using different getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_delete(Key::?RT:key(), Value::?DB:value(), WriteLock::boolean(),
                  ReadLock::0..10, Version::?DB:version(), Key2::?RT:key()) -> true.
prop_delete(Key, Value, WriteLock, ReadLock, Version, Key2) ->
    DB = ?TEST_DB:new(),
    DBEntry = create_db_entry(Key, Value, WriteLock, ReadLock, Version),
    DB2 = ?TEST_DB:set_entry(DB, DBEntry),
    
    % delete DBEntry:
    DB3 =
        case db_entry:is_locked(DBEntry) of
            true ->
                DBA1 = ?db_equals_pattern(?TEST_DB:delete(DB2, Key), locks_set),
                check_entry(DBA1, Key, DBEntry, {ok, Value, Version}, true, "check_entry_delete_1a"),
                case not db_entry:is_empty(DBEntry) andalso
                         not (db_entry:get_writelock(DBEntry) andalso db_entry:get_readlock(DBEntry) > 0) andalso
                         db_entry:get_version(DBEntry) >= 0 of
                    true -> check_db(DBA1, {true, []}, 1, [DBEntry], "check_db_delete_1ax");
                    _    -> check_db(DBA1, {false, [DBEntry]}, 1, [DBEntry], "check_db_delete_1ay")
                end,
                case Key =/= Key2 of
                    true ->
                        DBTmp = ?db_equals_pattern(?TEST_DB:delete(DBA1, Key2), undef),
                        check_entry(DBTmp, Key, DBEntry, {ok, Value, Version}, true, "check_entry_delete_2a"),
                        case not db_entry:is_empty(DBEntry) andalso
                                 not (db_entry:get_writelock(DBEntry) andalso db_entry:get_readlock(DBEntry) > 0) andalso
                                 db_entry:get_version(DBEntry) >= 0 of
                            true -> check_db(DBTmp, {true, []}, 1, [DBEntry], "check_db_delete_2ax");
                            _    -> check_db(DBTmp, {false, [DBEntry]}, 1, [DBEntry], "check_db_delete_2ay")
                        end,
                        DBTmp;
                    _ -> DBA1
                end;
            _ ->
                DBA1 = ?db_equals_pattern(?TEST_DB:delete(DB2, Key), ok),
                check_entry(DBA1, Key, db_entry:new(Key), {ok, empty_val, -1}, false, "check_entry_delete_1b"),
                check_db(DBA1, {true, []}, 0, [], "check_db_delete_1b"),
                DBA2 = ?db_equals_pattern(?TEST_DB:delete(DBA1, Key), undef),
                check_entry(DBA2, Key, db_entry:new(Key), {ok, empty_val, -1}, false, "check_entry_delete_2b"),
                check_db(DBA2, {true, []}, 0, [], "check_db_delete_2b"),
                DBA2
        end,
    
    ?TEST_DB:close(DB3),
    true.

tester_delete(_Config) ->
    tester:test(?MODULE, prop_delete, 6, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:add_data/2, also validate using different getters
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_add_data(Data::?TEST_DB:db_as_list()) -> true.
prop_add_data(Data) ->
    DB = ?TEST_DB:new(),
    
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    
    DB2 = ?TEST_DB:add_data(DB, Data),
    check_db2(DB2, length(UniqueData), UniqueData, "check_db_add_data_1"),
    
    ?TEST_DB:close(DB2),
    true.

tester_add_data(_Config) ->
    tester:test(?MODULE, prop_add_data, 1, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:get_entries/3 emulating the former get_range_kv/2 method
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_get_entries3_1(Data::?TEST_DB:db_as_list(), Range::intervals:interval()) -> true.
prop_get_entries3_1(Data, Range) ->
    DB = ?TEST_DB:new(),
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DB2 = ?TEST_DB:add_data(DB, UniqueData),
    
    FilterFun = fun(A) -> (not db_entry:is_empty(A)) andalso
                              intervals:in(db_entry:get_key(A), Range)
                end,
    ValueFun = fun(DBEntry) -> {db_entry:get_key(DBEntry),
                                db_entry:get_value(DBEntry)}
               end,
    
    ?equals_w_note(lists:sort(?TEST_DB:get_entries(DB2, FilterFun, ValueFun)),
                   lists:sort([ValueFun(A) || A <- lists:filter(FilterFun, UniqueData)]),
                   "check_get_entries3_1_1"),

    ?TEST_DB:close(DB2),
    true.

tester_get_entries3_1(_Config) ->
    tester:test(?MODULE, prop_get_entries3_1, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:get_entries/3 emulating the former get_range_kvv/2 method
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_get_entries3_2(Data::?TEST_DB:db_as_list(), Range::intervals:interval()) -> true.
prop_get_entries3_2(Data, Range) ->
    DB = ?TEST_DB:new(),
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DB2 = ?TEST_DB:add_data(DB, UniqueData),
    
    FilterFun = fun(A) -> (not db_entry:is_empty(A)) andalso
                              (not db_entry:get_writelock(A)) andalso
                              intervals:in(db_entry:get_key(A), Range)
                end,
    ValueFun = fun(DBEntry) -> {db_entry:get_key(DBEntry),
                                db_entry:get_value(DBEntry),
                                db_entry:get_version(DBEntry)}
               end,
    
    ?equals_w_note(lists:sort(?TEST_DB:get_entries(DB2, FilterFun, ValueFun)),
                   lists:sort([ValueFun(A) || A <- lists:filter(FilterFun, UniqueData)]),
                   "check_get_entries3_2_1"),

    ?TEST_DB:close(DB2),
    true.

tester_get_entries3_2(_Config) ->
    tester:test(?MODULE, prop_get_entries3_2, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:get_entries/2
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_get_entries2(Data::?TEST_DB:db_as_list(), Range::intervals:interval()) -> true.
prop_get_entries2(Data, Range) ->
    DB = ?TEST_DB:new(),
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DB2 = ?TEST_DB:add_data(DB, UniqueData),
    
    InRangeFun = fun(A) -> (not db_entry:is_empty(A)) andalso
                               intervals:in(db_entry:get_key(A), Range)
                 end,
    
    ?equals_w_note(lists:sort(?TEST_DB:get_entries(DB2, Range)),
                   lists:sort(lists:filter(InRangeFun, UniqueData)),
                   "check_get_entries2_1"),

    ?TEST_DB:close(DB2),
    true.

tester_get_entries2(_Config) ->
    tester:test(?MODULE, prop_get_entries2, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:get_load/2
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_get_load2(Data::?TEST_DB:db_as_list(), LoadInterval::intervals:interval()) -> true.
prop_get_load2(Data, LoadInterval) ->
    DB = ?TEST_DB:new(),
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DB2 = ?TEST_DB:add_data(DB, UniqueData),
    
    FilterFun = fun(A) -> intervals:in(db_entry:get_key(A), LoadInterval) end,
    ValueFun = fun(_DBEntry) -> 1 end,
    
    ?equals_w_note(?TEST_DB:get_load(DB2, LoadInterval),
                   length(lists:filter(FilterFun, UniqueData)),
                   "check_get_load2_1"),
    ?equals_w_note(?TEST_DB:get_load(DB2, LoadInterval),
                   length(?TEST_DB:get_entries(DB2, FilterFun, ValueFun)),
                   "check_get_load2_2"),

    ?TEST_DB:close(DB2),
    true.

tester_get_load2(_Config) ->
    tester:test(?MODULE, prop_get_load2, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:split_data/2
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_split_data(Data::?TEST_DB:db_as_list(), Range::intervals:interval()) -> true.
prop_split_data(Data, Range) ->
    DB = ?TEST_DB:new(),
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DB2 = ?TEST_DB:add_data(DB, UniqueData),
    
    InHisRangeFun = fun(A) -> (not db_entry:is_empty(A)) andalso
                                  (not intervals:in(db_entry:get_key(A), Range))
                    end,
    InMyRangeFun = fun(A) -> intervals:in(db_entry:get_key(A), Range) end,
    
    {DB3, HisList} = ?TEST_DB:split_data(DB2, Range),
    ?equals_w_note(lists:sort(HisList),
                   lists:sort(lists:filter(InHisRangeFun, UniqueData)),
                   "check_split_data_1"),
    ?equals_w_note(lists:sort(?TEST_DB:get_data(DB3)),
                   lists:sort(lists:filter(InMyRangeFun, UniqueData)),
                   "check_split_data_2"),

    ?TEST_DB:close(DB3),
    true.

tester_split_data(_Config) ->
    tester:test(?MODULE, prop_split_data, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:update_entries/4
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_update_entries(Data::?TEST_DB:db_as_list(), ItemsToUpdate::pos_integer()) -> true.
prop_update_entries(Data, ItemsToUpdate) ->
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    UniqueUpdateData =
        [db_entry:inc_version(E) || E <- lists:sublist(UniqueData, ItemsToUpdate)],
    ExpUpdatedData =
        [begin
             case db_entry:is_locked(E) of
                 true -> E;
                 _    ->
                     EUpd = [X || X <- UniqueUpdateData,
                                  db_entry:get_key(X) =:= db_entry:get_key(E),
                                  db_entry:get_version(X) > db_entry:get_version(E)],
                     case EUpd of
                         []  -> E;
                         [X] -> X
                     end
             end
         end || E <- UniqueData] ++
        [E || E <- UniqueUpdateData,
              not lists:any(fun(X) ->
                                    db_entry:get_key(X) =:= db_entry:get_key(E)
                            end, UniqueData)],
    
    prop_update_entries_helper(UniqueData, UniqueUpdateData, ExpUpdatedData).

-spec prop_update_entries_helper(UniqueData::?TEST_DB:db_as_list(), UniqueUpdateData::?TEST_DB:db_as_list(), ExpUpdatedData::?TEST_DB:db_as_list()) -> true.
prop_update_entries_helper(UniqueData, UniqueUpdateData, ExpUpdatedData) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, UniqueData),
    
    UpdatePred = fun(OldEntry, NewEntry) ->
                         db_entry:get_version(OldEntry) < db_entry:get_version(NewEntry)
                 end,
    UpdateVal = fun(_OldEntry, NewEntry) -> NewEntry end,
    
    DB3 = ?TEST_DB:update_entries(DB2, UniqueUpdateData, UpdatePred, UpdateVal),
    
    ?equals_w_note(lists:sort(?TEST_DB:get_data(DB3)),
                   lists:sort(ExpUpdatedData),
                   "check_update_entries_1"),

    ?TEST_DB:close(DB3),
    true.

tester_update_entries(_Config) ->
    tester:test(?MODULE, prop_update_entries, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:delete_entries/2
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_delete_entries1(Data::?TEST_DB:db_as_list(), Range::intervals:interval()) -> true.
prop_delete_entries1(Data, Range) ->
    % use a range to delete entries
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    
    DB3 = ?TEST_DB:delete_entries(DB2, Range),
    
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    UniqueRemainingData = [DBEntry || DBEntry <- UniqueData,
                                      not intervals:in(db_entry:get_key(DBEntry), Range)],
    check_db2(DB3, length(UniqueRemainingData), UniqueRemainingData, "check_db_delete_entries1_1"),
    
    ?TEST_DB:close(DB3),
    true.

-spec prop_delete_entries2(Data::?TEST_DB:db_as_list(), Range::intervals:interval()) -> true.
prop_delete_entries2(Data, Range) ->
    % use a range to delete entries
    FilterFun = fun(DBEntry) -> not intervals:in(db_entry:get_key(DBEntry), Range) end,
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    
    DB3 = ?TEST_DB:delete_entries(DB2, FilterFun),
    
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    UniqueRemainingData = [DBEntry || DBEntry <- UniqueData,
                                      intervals:in(db_entry:get_key(DBEntry), Range)],
    check_db2(DB3, length(UniqueRemainingData), UniqueRemainingData, "check_db_delete_entries2_1"),
    
    ?TEST_DB:close(DB3),
    true.

tester_delete_entries1(_Config) ->
    tester:test(?MODULE, prop_delete_entries1, 2, rw_suite_runs(1000), [{threads, 2}]).

tester_delete_entries2(_Config) ->
    tester:test(?MODULE, prop_delete_entries2, 2, rw_suite_runs(1000), [{threads, 2}]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% ?TEST_DB:record_changes/2, stop_record_changes/1 and get_changes/1
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec prop_changed_keys_get_entry(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Key::?RT:key()) -> true.
prop_changed_keys_get_entry(Data, ChangesInterval, Key) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),

    ?TEST_DB:get_entry(DB3, Key),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_get_entry_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_get_entry_2"),
    
    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_set_entry(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Entry::db_entry:entry()) -> true.
prop_changed_keys_set_entry(Data, ChangesInterval, Entry) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    Old = ?TEST_DB:get_entry2(DB2, db_entry:get_key(Entry)),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    DB4 = ?TEST_DB:set_entry(DB3, Entry),
    check_changes(DB4, ChangesInterval, "changed_keys_set_entry_1"),
    check_entry_in_changes(DB4, ChangesInterval, Entry, Old, "changed_keys_set_entry_2"),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "changed_keys_set_entry_3"),

    ?TEST_DB:close(DB5),
    true.


-spec prop_changed_keys_update_entry(
        Data::[db_entry:entry(),...], ChangesInterval::intervals:interval(),
        UpdateVal::?TEST_DB:value()) -> true.
prop_changed_keys_update_entry(Data, ChangesInterval, UpdateVal) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    UpdateElement = util:randomelem(UniqueData),
    Old = ?TEST_DB:get_entry2(DB2, db_entry:get_key(UpdateElement)),
    UpdatedElement = db_entry:inc_version(db_entry:set_value(UpdateElement, UpdateVal)),
    
    case element(1, Old) of
        false -> % element does not exist, i.e. was a null entry, -> cannot update
            DB5 = DB2;
        _ ->
            DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
            DB4 = ?TEST_DB:update_entry(DB3, UpdatedElement),
            check_changes(DB4, ChangesInterval, "changed_update_entry_1"),
            check_entry_in_changes(DB4, ChangesInterval, UpdatedElement, Old, "changed_update_entry_2"),
            
            DB5 = check_stop_record_changes(DB4, ChangesInterval, "changed_update_entry_3")
    end,

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_delete_entry(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Entry::db_entry:entry()) -> true.
prop_changed_keys_delete_entry(Data, ChangesInterval, Entry) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    Old = ?TEST_DB:get_entry2(DB2, db_entry:get_key(Entry)),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    DB4 = ?TEST_DB:delete_entry(DB3, Entry),
    check_changes(DB4, ChangesInterval, "delete_entry_1"),
    check_key_in_deleted_no_locks(DB4, ChangesInterval, db_entry:get_key(Entry), Old, "delete_entry_2"),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "delete_entry_3"),

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_read(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Key::?RT:key()) -> true.
prop_changed_keys_read(Data, ChangesInterval, Key) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    ?TEST_DB:read(DB3, Key),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_read_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_read_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_write(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Key::?RT:key(), Value::?TEST_DB:value(), Version::?TEST_DB:version()) -> true.
prop_changed_keys_write(Data, ChangesInterval, Key, Value, Version) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    Old = ?TEST_DB:get_entry2(DB2, Key),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    DB4 = ?TEST_DB:write(DB3, Key, Value, Version),
    check_changes(DB4, ChangesInterval, "changed_keys_write_1"),
    ChangedEntry = ?TEST_DB:get_entry(DB4, Key),
    check_entry_in_changes(DB4, ChangesInterval, ChangedEntry, Old, "changed_keys_write_2"),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "changed_keys_write_3"),

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_delete(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Key::?RT:key()) -> true.
prop_changed_keys_delete(Data, ChangesInterval, Key) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    Old = ?TEST_DB:get_entry2(DB2, Key),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    {DB4, _Status} = ?TEST_DB:delete(DB3, Key),
    check_changes(DB4, ChangesInterval, "delete_1"),
    check_key_in_deleted_no_locks(DB4, ChangesInterval, Key, Old, "delete_2"),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "delete_3"),

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_get_entries2(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Interval::intervals:interval()) -> true.
prop_changed_keys_get_entries2(Data, ChangesInterval, Interval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    ?TEST_DB:get_entries(DB3, Interval),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_get_entries2_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_get_entries2_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_get_entries4(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Interval::intervals:interval()) -> true.
prop_changed_keys_get_entries4(Data, ChangesInterval, Interval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    FilterFun = fun(E) -> (not db_entry:is_empty(E)) andalso
                              (not intervals:in(db_entry:get_key(E), Interval))
                end,
    ValueFun = fun(E) -> db_entry:get_key(E) end,
    
    ?TEST_DB:get_entries(DB3, FilterFun, ValueFun),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_get_entries4_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_get_entries4_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_get_chunk3(Keys::[?RT:key()], Interval::intervals:interval(), ChunkSize::pos_integer() | all) -> true.
prop_get_chunk3(Keys2, Interval, ChunkSize) ->
    case not intervals:is_empty(Interval) of
        true ->
            Keys = lists:usort(Keys2),
            DB = ?TEST_DB:new(),
            DB2 = lists:foldl(fun(Key, DBA) -> ?TEST_DB:write(DBA, Key, "Value", 1) end, DB, Keys),
            {Next, Chunk} = ?TEST_DB:get_chunk(DB2, Interval, ChunkSize),
            ?TEST_DB:close(DB2),
            ?equals(lists:usort(Chunk), lists:sort(Chunk)), % check for duplicates
            KeysInRange = count_keys_in_range(Keys, Interval),
            ExpectedChunkSize =
                case ChunkSize of
                    all -> KeysInRange;
                    _   -> erlang:min(KeysInRange, ChunkSize)
                end,
            case ExpectedChunkSize =/= length(Chunk) of
                true ->
                    ?ct_fail("chunk has wrong size ~.0p ~.0p ~.0p, expected size: ~.0p",
                             [Chunk, Keys, Interval, ExpectedChunkSize]);
                false ->
                    ?equals([Entry || Entry <- Chunk,
                                      not intervals:in(db_entry:get_key(Entry), Interval)],
                            [])
            end,
            % Next if subset of Interval, no chunk entry is in Next:
            ?equals_w_note(intervals:is_subset(Next, Interval), true,
                           io_lib:format("Next ~.0p is not subset of ~.0p",
                                         [Next, Interval])),
            ?equals_w_note([Entry || Entry <- Chunk,
                                     intervals:in(db_entry:get_key(Entry), Next)],
                           [], io_lib:format("Next: ~.0p", [Next]));
        _ -> true
    end.

-spec prop_delete_chunk3(Keys::[?RT:key()], Interval::intervals:interval(), ChunkSize::pos_integer() | all) -> true.
prop_delete_chunk3(Keys2, Interval, ChunkSize) ->
    case not intervals:is_empty(Interval) of
        true ->
            Keys = lists:usort(Keys2),
            DB = ?TEST_DB:new(),
            DB2 = lists:foldl(fun(Key, DBA) -> ?TEST_DB:write(DBA, Key, "Value", 1) end, DB, Keys),
            {Next_GC, Chunk} = ?TEST_DB:get_chunk(DB2, Interval, ChunkSize),
            {Next_DC, DB3} = ?TEST_DB:delete_chunk(DB2, Interval, ChunkSize),
            ?equals(Next_GC, Next_DC),
            PostDeleteChunkSize = ?TEST_DB:get_load(DB3),
            DB5 = lists:foldl(fun (Entry, DB4) -> ?TEST_DB:delete_entry(DB4, Entry) end, DB3, Chunk),
            PostDeleteSize = ?TEST_DB:get_load(DB5),
            ?TEST_DB:close(DB5),
            ?equals(PostDeleteChunkSize, PostDeleteSize), % delete should have deleted all items in Chunk
            ?equals(length(Keys) - length(Chunk), PostDeleteSize); % delete should have deleted all items in Chunk
        _ -> true
    end.

-spec prop_changed_keys_update_entries(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        Entry1::db_entry:entry(), Entry2::db_entry:entry()) -> true.
prop_changed_keys_update_entries(Data, ChangesInterval, Entry1, Entry2) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    Old1 = ?TEST_DB:get_entry2(DB2, db_entry:get_key(Entry1)),
    Old2 = ?TEST_DB:get_entry2(DB2, db_entry:get_key(Entry2)),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    UpdatePred = fun(OldEntry, NewEntry) ->
                         db_entry:get_version(OldEntry) < db_entry:get_version(NewEntry)
                 end,
    UpdateVal = fun(_OldEntry, NewEntry) -> NewEntry end,

    DB4 = ?TEST_DB:update_entries(DB3, [Entry1, Entry2], UpdatePred, UpdateVal),
    NewEntry1 = ?TEST_DB:get_entry(DB4, db_entry:get_key(Entry1)),
    NewEntry2 = ?TEST_DB:get_entry(DB4, db_entry:get_key(Entry2)),
    check_changes(DB4, ChangesInterval, "update_entries_1"),
    ?implies(db_entry:get_version(element(2, Old1)) < db_entry:get_version(Entry1),
             check_entry_in_changes(DB4, ChangesInterval, NewEntry1, Old1, "update_entries_2")),
    ?implies(db_entry:get_version(element(2, Old2)) < db_entry:get_version(Entry2),
             check_entry_in_changes(DB4, ChangesInterval, NewEntry2, Old2, "update_entries_3")),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "update_entries_4"),

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_delete_entries1(
        Data::?TEST_DB:db_as_list(), Range::intervals:interval(),
        ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_delete_entries1(Data, ChangesInterval, Range) ->
    % use a range to delete entries
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    DB4 = ?TEST_DB:delete_entries(DB3, Range),
    
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DeletedKeys = [{db_entry:get_key(DBEntry), true}
                  || DBEntry <- UniqueData,
                     intervals:in(db_entry:get_key(DBEntry), Range)],
    check_changes(DB4, ChangesInterval, "delete_entries1_1"),
    check_keys_in_deleted(DB4, ChangesInterval, DeletedKeys, "delete_entries1_2"),
    
    ?TEST_DB:close(DB3),
    true.

-spec prop_changed_keys_delete_entries2(
        Data::?TEST_DB:db_as_list(), Range::intervals:interval(),
        ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_delete_entries2(Data, ChangesInterval, Range) ->
    % use a range to delete entries
    FilterFun = fun(DBEntry) -> not intervals:in(db_entry:get_key(DBEntry), Range) end,
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    DB4 = ?TEST_DB:delete_entries(DB3, FilterFun),
    
    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    DeletedKeys = [{db_entry:get_key(DBEntry), true}
                  || DBEntry <- UniqueData,
                     not intervals:in(db_entry:get_key(DBEntry), Range)],
    check_changes(DB4, ChangesInterval, "delete_entries2_1"),
    check_keys_in_deleted(DB4, ChangesInterval, DeletedKeys, "delete_entries2_2"),
    
    ?TEST_DB:close(DB3),
    true.

-spec prop_changed_keys_get_load(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_get_load(Data, ChangesInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    ?TEST_DB:get_load(DB3),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_get_load_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_get_load_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_get_load2(
        Data::?TEST_DB:db_as_list(), LoadInterval::intervals:interval(),
        ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_get_load2(Data, LoadInterval, ChangesInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    ?TEST_DB:get_load(DB3, LoadInterval),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_get_load2_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_get_load2_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_split_data1(
        Data::?TEST_DB:db_as_list(),
        ChangesInterval::intervals:interval(),
        MyNewInterval1::intervals:interval()) -> true.
prop_changed_keys_split_data1(Data, ChangesInterval, MyNewInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),

    {DB4, _HisList} = ?TEST_DB:split_data(DB3, MyNewInterval),
    ?equals_w_note(?TEST_DB:get_changes(DB4), {[], []}, "split_data1_1"),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "split_data1_2"),

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_split_data2(
        Data::?TEST_DB:db_as_list(),
        ChangesInterval::intervals:interval(),
        MyNewInterval1::intervals:interval()) -> true.
prop_changed_keys_split_data2(Data, ChangesInterval, MyNewInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:record_changes(DB, ChangesInterval),
    DB3 = ?TEST_DB:add_data(DB2, Data),

    {DB4, _HisList} = ?TEST_DB:split_data(DB3, MyNewInterval),
    
    check_changes(DB4, intervals:intersection(ChangesInterval, MyNewInterval), "split_data2_1"),
    
    DB5 = check_stop_record_changes(DB4, ChangesInterval, "split_data2_2"),

    ?TEST_DB:close(DB5),
    true.

-spec prop_changed_keys_get_data(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_get_data(Data, ChangesInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    ?TEST_DB:get_data(DB3),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_get_data_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_get_data_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_add_data(
        Data::?TEST_DB:db_as_list(),
        ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_add_data(Data, ChangesInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:record_changes(DB, ChangesInterval),
    
    DB3 = ?TEST_DB:add_data(DB2, Data),
    check_changes(DB3, ChangesInterval, "add_data_1"),

    % lists:usort removes all but first occurrence of equal elements
    % -> reverse list since ?TEST_DB:add_data will keep the last element
    UniqueData = lists:usort(fun(A, B) ->
                                     db_entry:get_key(A) =< db_entry:get_key(B)
                             end, lists:reverse(Data)),
    _ = [check_entry_in_changes(DB3, ChangesInterval, E, {false, db_entry:new(db_entry:get_key(E))}, "add_data_2")
           || E <- UniqueData],
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "add_data_3"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_check_db(
        Data::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval()) -> true.
prop_changed_keys_check_db(Data, ChangesInterval) ->
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    DB3 = ?TEST_DB:record_changes(DB2, ChangesInterval),
    
    ?TEST_DB:check_db(DB3),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, "changed_keys_check_db_1"),
    
    DB4 = check_stop_record_changes(DB3, ChangesInterval, "changed_keys_check_db_2"),

    ?TEST_DB:close(DB4),
    true.

-spec prop_changed_keys_mult_interval(
        Data::?TEST_DB:db_as_list(), Entry1::db_entry:entry(),
        Entry2::db_entry:entry(), Entry3::db_entry:entry(),
        Entry4::db_entry:entry()) -> true.
prop_changed_keys_mult_interval(Data, Entry1, Entry2, Entry3, Entry4) ->
    CI1 = intervals:union(intervals:new(db_entry:get_key(Entry1)),
                          intervals:new(db_entry:get_key(Entry2))),
    CI2 = intervals:union(intervals:new(db_entry:get_key(Entry3)),
                          intervals:new(db_entry:get_key(Entry4))),
    CI1_2 = intervals:union(CI1, CI2),
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    
    DB3 = ?TEST_DB:record_changes(DB2, CI1),
    Old1 = ?TEST_DB:get_entry2(DB3, db_entry:get_key(Entry1)),
    DB4 = ?TEST_DB:set_entry(DB3, Entry1),
    check_changes(DB4, CI1, "changed_keys_mult_interval_1"),
    check_entry_in_changes(DB4, CI1, Entry1, Old1, "changed_keys_mult_interval_2"),
    
    DB5 = ?TEST_DB:record_changes(DB4, CI2),
    Old2 = ?TEST_DB:get_entry2(DB5, db_entry:get_key(Entry2)),
    DB6 = ?TEST_DB:set_entry(DB5, Entry2),
    check_changes(DB6, CI1_2, "changed_keys_mult_interval_3"),
    check_entry_in_changes(DB6, CI1_2, Entry2, Old2, "changed_keys_mult_interval_4"),
    
    DB7 = ?TEST_DB:record_changes(DB6, CI2),
    Old3 = ?TEST_DB:get_entry2(DB7, db_entry:get_key(Entry3)),
    DB8 = ?TEST_DB:set_entry(DB7, Entry3),
    check_changes(DB8, CI1_2, "changed_keys_mult_interval_5"),
    check_entry_in_changes(DB8, CI1_2, Entry3, Old3, "changed_keys_mult_interval_6"),
    
    DB9 = ?TEST_DB:record_changes(DB8, CI2),
    Old4 = ?TEST_DB:get_entry2(DB9, db_entry:get_key(Entry4)),
    DB10 = ?TEST_DB:set_entry(DB9, Entry4),
    check_changes(DB10, CI1_2, "changed_keys_mult_interval_7"),
    check_entry_in_changes(DB10, CI1_2, Entry4, Old4, "changed_keys_mult_interval_8"),
    
    DB11 = check_stop_record_changes(DB10, CI1_2, "changed_keys_mult_interval_9"),

    ?TEST_DB:close(DB11),
    true.

-spec prop_stop_record_changes(
        Data::?TEST_DB:db_as_list(), Entry1::db_entry:entry(),
        Entry2::db_entry:entry(), Entry3::db_entry:entry(),
        Entry4::db_entry:entry()) -> true.
prop_stop_record_changes(Data, Entry1, Entry2, Entry3, Entry4) ->
    CI1 = intervals:union(intervals:new(db_entry:get_key(Entry1)),
                          intervals:new(db_entry:get_key(Entry2))),
    CI2 = intervals:union(intervals:new(db_entry:get_key(Entry3)),
                          intervals:new(db_entry:get_key(Entry4))),
    CI1_2 = intervals:union(CI1, CI2),
    CI1_wo2 = intervals:minus(CI1, CI2),
    DB = ?TEST_DB:new(),
    DB2 = ?TEST_DB:add_data(DB, Data),
    
    DB3 = ?TEST_DB:record_changes(DB2, CI1_2),
    Old1 = ?TEST_DB:get_entry2(DB3, db_entry:get_key(Entry1)),
    DB4 = ?TEST_DB:set_entry(DB3, Entry1),
    check_changes(DB4, CI1_2, "stop_record_changes_1"),
    check_entry_in_changes(DB4, CI1_2, Entry1, Old1, "stop_record_changes_2"),
    
    Old3 = ?TEST_DB:get_entry2(DB4, db_entry:get_key(Entry3)),
    DB5 = ?TEST_DB:set_entry(DB4, Entry3),
    check_changes(DB5, CI1_2, "stop_record_changes_3"),
    check_entry_in_changes(DB5, CI1_2, Entry3, Old3, "stop_record_changes_4"),
    
    DB6 = ?TEST_DB:stop_record_changes(DB5, CI2),
    check_changes(DB6, CI1_wo2, "stop_record_changes_5"),
    check_entry_in_changes(DB6, CI1_wo2, Entry1, Old1, "stop_record_changes_6"),
    
    Old2 = ?TEST_DB:get_entry2(DB6, db_entry:get_key(Entry2)),
    DB7 = ?TEST_DB:set_entry(DB6, Entry2),
    check_changes(DB7, CI1_wo2, "stop_record_changes_7"),
    check_entry_in_changes(DB7, CI1_wo2, Entry2, Old2, "stop_record_changes_8"),
    
    Old4 = ?TEST_DB:get_entry2(DB7, db_entry:get_key(Entry4)),
    DB8 = ?TEST_DB:set_entry(DB7, Entry4),
    check_changes(DB8, CI1_wo2, "stop_record_changes_9"),
    check_entry_in_changes(DB8, CI1_wo2, Entry4, Old4, "stop_record_changes_10"),
    
    DB9 = ?TEST_DB:stop_record_changes(DB8),
    ?equals_w_note(?TEST_DB:get_changes(DB9), {[], []}, "stop_record_changes_11"),

    ?TEST_DB:close(DB9),
    true.

tester_changed_keys_get_entry(_Config) ->
    tester:test(?MODULE, prop_changed_keys_get_entry, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_set_entry(_Config) ->
    tester:test(?MODULE, prop_changed_keys_set_entry, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_update_entry(_Config) ->
    tester:test(?MODULE, prop_changed_keys_update_entry, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_delete_entry(_Config) ->
    tester:test(?MODULE, prop_changed_keys_delete_entry, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_read(_Config) ->
    tester:test(?MODULE, prop_changed_keys_read, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_write(_Config) ->
    tester:test(?MODULE, prop_changed_keys_write, 5, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_delete(_Config) ->
    tester:test(?MODULE, prop_changed_keys_delete, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_get_entries2(_Config) ->
    tester:test(?MODULE, prop_changed_keys_get_entries2, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_get_entries4(_Config) ->
    tester:test(?MODULE, prop_changed_keys_get_entries4, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_get_chunk3(_Config) ->
    prop_get_chunk3([0, 4, 31], intervals:new('[', 0, 4, ']'), 2),
    prop_get_chunk3([1, 5, 127, 13], intervals:new('[', 3, 2, ']'), 4),
    tester:test(?MODULE, prop_get_chunk3, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_delete_chunk3(_Config) ->
    tester:test(?MODULE, prop_delete_chunk3, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_update_entries(_Config) ->
    prop_changed_keys_update_entries(
      [{?RT:hash_key("200"),empty_val,false,0,-1}], intervals:all(),
      {?RT:hash_key("100"),empty_val,false,1,-1}, {?RT:hash_key("200"),empty_val,false,296,-1}),
    tester:test(?MODULE, prop_changed_keys_update_entries, 4, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_delete_entries1(_Config) ->
    tester:test(?MODULE, prop_changed_keys_delete_entries1, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_delete_entries2(_Config) ->
    tester:test(?MODULE, prop_changed_keys_delete_entries2, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_get_load(_Config) ->
    tester:test(?MODULE, prop_changed_keys_get_load, 2, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_get_load2(_Config) ->
    tester:test(?MODULE, prop_changed_keys_get_load2, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_split_data1(_Config) ->
    tester:test(?MODULE, prop_changed_keys_split_data1, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_split_data2(_Config) ->
    tester:test(?MODULE, prop_changed_keys_split_data2, 3, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_get_data(_Config) ->
    tester:test(?MODULE, prop_changed_keys_get_data, 2, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_add_data(_Config) ->
    tester:test(?MODULE, prop_changed_keys_add_data, 2, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_check_db(_Config) ->
    tester:test(?MODULE, prop_changed_keys_check_db, 2, rw_suite_runs(1000), [{threads, 2}]).

tester_changed_keys_mult_interval(_Config) ->
    tester:test(?MODULE, prop_changed_keys_mult_interval, 5, rw_suite_runs(1000), [{threads, 2}]).

tester_stop_record_changes(_Config) ->
    tester:test(?MODULE, prop_stop_record_changes, 5, rw_suite_runs(1000), [{threads, 2}]).


% helper functions:

-spec check_entry(DB::?TEST_DB:db(), Key::?RT:key(), ExpDBEntry::db_entry:entry(),
                  ExpRead::{ok, Value::?TEST_DB:value(), Version::?TEST_DB:version()} | {ok, empty_val, -1},
                  ExpExists::boolean(), Note::string()) -> true.
check_entry(DB, Key, ExpDBEntry, ExpRead, ExpExists, Note) ->
    ?equals_w_note(?TEST_DB:get_entry2(DB, Key), {ExpExists, ExpDBEntry}, Note),
    ?equals_w_note(?TEST_DB:get_entry(DB, Key), ExpDBEntry, Note),
    ?equals_w_note(?TEST_DB:read(DB, Key), ExpRead, Note).

% note: use manageable values for ReadLock!
-spec create_db_entry(Key::?RT:key(), Value::?DB:value(), WriteLock::boolean(),
                      ReadLock::0..1000, Version::?DB:version() | -1) -> db_entry:entry().
create_db_entry(Key, Value, WriteLock, ReadLock, Version) ->
    E1 = db_entry:new(Key, Value, Version),
    E2 = case WriteLock of
             true -> db_entry:set_writelock(E1);
             _    -> E1
         end,
    _E3 = inc_readlock(E2, ReadLock).

-spec inc_readlock(DBEntry::db_entry:entry(), Count::non_neg_integer()) -> db_entry:entry().
inc_readlock(DBEntry, 0) -> DBEntry;
inc_readlock(DBEntry, Count) -> inc_readlock(db_entry:inc_readlock(DBEntry), Count - 1).

-spec check_db(DB::?TEST_DB:db(),
               ExpCheckDB::{true, []} | {false, InvalidEntries::?TEST_DB:db_as_list()},
               ExpLoad::integer(),
               ExpData::?TEST_DB:db_as_list(), Note::string()) -> true.
check_db(DB, ExpCheckDB, ExpLoad, ExpData, Note) ->
    check_db(DB, ExpCheckDB, ExpLoad, ExpData, {[], []}, Note).

-spec check_db(DB::?TEST_DB:db(),
               ExpCheckDB::{true, []} | {false, InvalidEntries::?TEST_DB:db_as_list()},
               ExpLoad::integer(),
               ExpData::?TEST_DB:db_as_list(),
               ExpCKData::{UpdatedEntries::?TEST_DB:db_as_list(), DeletedKeys::[?RT:key()]},
               Note::string()) -> true.
check_db(DB, ExpCheckDB, ExpLoad, ExpData, ExpCKData, Note) ->
    ?equals_w_note(?TEST_DB:check_db(DB), ExpCheckDB, Note),
    ?equals_w_note(?TEST_DB:get_load(DB), ExpLoad, Note),
    ?equals_w_note(lists:sort(?TEST_DB:get_data(DB)), lists:sort(ExpData), Note),
    ?equals_w_note(?TEST_DB:get_changes(DB), ExpCKData, Note).

%% @doc Like check_db/5 but do not check DB using ?TEST_DB:check_db.
-spec check_db2(DB::?TEST_DB:db(), ExpLoad::integer(),
               ExpData::?TEST_DB:db_as_list(), Note::string()) -> true.
check_db2(DB, ExpLoad, ExpData, Note) ->
    check_db2(DB, ExpLoad, ExpData, {[], []}, Note).

%% @doc Like check_db/5 but do not check DB using ?TEST_DB:check_db.
-spec check_db2(DB::?TEST_DB:db(), ExpLoad::integer(),
                ExpData::?TEST_DB:db_as_list(),
                ExpCKData::{UpdatedEntries::?TEST_DB:db_as_list(), DeletedKeys::[?RT:key()]},
                Note::string()) -> true.
check_db2(DB, ExpLoad, ExpData, ExpCKData, Note) ->
    ?equals_w_note(?TEST_DB:get_load(DB), ExpLoad, Note),
    ?equals_w_note(lists:sort(?TEST_DB:get_data(DB)), lists:sort(ExpData), Note),
    ?equals_w_note(?TEST_DB:get_changes(DB), ExpCKData, Note).

get_random_interval_from_changes(DB) ->
    {ChangedEntries, DeletedKeys} = ?TEST_DB:get_changes(DB),
    case ChangedEntries =/= [] orelse DeletedKeys =/= [] of
        true ->
            intervals:new(util:randomelem(
                            lists:append(
                              [db_entry:get_key(E) || E <- ChangedEntries],
                              DeletedKeys)));
        _    -> intervals:empty()
    end.

-spec check_stop_record_changes(DB::?TEST_DB:db(), ChangesInterval::intervals:interval(), Note::string()) -> ?TEST_DB:db().
check_stop_record_changes(DB, ChangesInterval, Note) ->
    I1 = get_random_interval_from_changes(DB),
    DB2 = ?TEST_DB:stop_record_changes(DB, I1),
    check_changes(DB2, intervals:minus(ChangesInterval, I1), Note ++ "a"),

    DB3 = ?TEST_DB:stop_record_changes(DB2),
    ?equals_w_note(?TEST_DB:get_changes(DB3), {[], []}, Note ++ "b"),

    DB3.


%% @doc Checks that all entries returned by ?TEST_DB:get_changes/1 are in the
%%      given interval.
-spec check_changes(DB::?TEST_DB:db(), ChangesInterval::intervals:interval(), Note::string()) -> true.
check_changes(DB, ChangesInterval, Note) ->
    {ChangedEntries1, DeletedKeys1} = ?TEST_DB:get_changes(DB),
    case lists:all(fun(E) -> intervals:in(db_entry:get_key(E), ChangesInterval) end,
               ChangedEntries1) of
        false ->
            ?ct_fail("~s evaluated to \"~w\" and contains elements not in ~w~n(~s)~n",
                     ["element(1, ?TEST_DB:get_changes(DB))", ChangedEntries1,
                      ChangesInterval, lists:flatten(Note)]);
        _ -> ok
    end,
    case lists:all(fun(E) -> intervals:in(E, ChangesInterval) end, DeletedKeys1) of
        false ->
            ?ct_fail("~s evaluated to \"~w\" and contains elements not in ~w~n(~s)~n",
                     ["element(2, ?TEST_DB:get_changes(DB))", DeletedKeys1,
                      ChangesInterval, lists:flatten(Note)]);
        _ -> ok
    end,
    check_changes2(DB, ChangesInterval, ChangesInterval, Note),
    % select some random key from the changed entries and try get_changes/2
    % with an interval that does not contain this key
    case ChangedEntries1 =/= [] orelse DeletedKeys1 =/= [] of
        true ->
            SomeKey = util:randomelem(
                        lists:append(
                          [db_entry:get_key(E) || E <- ChangedEntries1],
                          DeletedKeys1)),
            check_changes2(DB, ChangesInterval, intervals:minus(ChangesInterval, intervals:new(SomeKey)), Note);
        _    -> true
    end.

%% @doc Checks that all entries returned by ?TEST_DB:get_changes/2 are in the
%%      given interval GetChangesInterval and also ChangesInterval.
-spec check_changes2(DB::?TEST_DB:db(), ChangesInterval::intervals:interval(), GetChangesInterval::intervals:interval(), Note::string()) -> true.
check_changes2(DB, ChangesInterval, GetChangesInterval, Note) ->
    {ChangedEntries2, DeletedKeys2} = ?TEST_DB:get_changes(DB, GetChangesInterval),
    FinalInterval = intervals:intersection(ChangesInterval, GetChangesInterval),
    case lists:all(fun(E) -> intervals:in(db_entry:get_key(E), FinalInterval) end,
               ChangedEntries2) of
        false ->
            ?ct_fail("~s evaluated to \"~w\" and contains elements not in ~w~n(~s)~n",
                     ["element(1, ?TEST_DB:get_changes(DB, FinalInterval))",
                      ChangedEntries2, FinalInterval, lists:flatten(Note)]);
        _ -> ok
    end,
    case lists:all(fun(E) -> intervals:in(E, FinalInterval) end, DeletedKeys2) of
        false ->
            ?ct_fail("~s evaluated to \"~w\" and contains elements not in ~w~n(~s)~n",
                     ["element(2, ?TEST_DB:get_changes(DB, FinalInterval))",
                      DeletedKeys2, FinalInterval, lists:flatten(Note)]);
        _ -> ok
    end,
    true.

%% @doc Checks that a key is present exactly once in the list of deleted
%%      keys returned by ?TEST_DB:get_changes/1 if no lock is set on a
%%      previously existing entry.
-spec check_key_in_deleted_no_locks(
        DB::?TEST_DB:db(), ChangesInterval::intervals:interval(), Key::?RT:key(),
        {OldExists::boolean(), OldEntry::db_entry:entry()}, Note::string()) -> true.
check_key_in_deleted_no_locks(DB, ChangesInterval, Key, {OldExists, OldEntry}, Note) ->
    case intervals:in(Key, ChangesInterval) andalso OldExists andalso
             not db_entry:is_locked(OldEntry) of
        true ->
            {_ChangedEntries, DeletedKeys} = ?TEST_DB:get_changes(DB),
            check_key_in_deleted_internal(DeletedKeys, ChangesInterval, Key, OldExists, Note);
        _    -> true
    end.

%% @doc Checks that all given keys are present exactly once in the list of
%%      deleted keys returned by ?TEST_DB:get_changes/1.
-spec check_keys_in_deleted(
        DB::?TEST_DB:db(), ChangesInterval::intervals:interval(),
        Keys::[{?RT:key(), OldExists::boolean()}], Note::string()) -> true.
check_keys_in_deleted(DB, ChangesInterval, Keys, Note) ->
    {_ChangedEntries, DeletedKeys} = ?TEST_DB:get_changes(DB),
    [check_key_in_deleted_internal(DeletedKeys, ChangesInterval, Key, OldExists, Note)
    || {Key, OldExists} <- Keys],
    true.

-spec check_key_in_deleted_internal(
        DeletedKeys::intervals:interval(), ChangesInterval::intervals:interval(),
        Key::?RT:key(), OldExists::boolean(), Note::string()) -> true.
check_key_in_deleted_internal(DeletedKeys, ChangesInterval, Key, OldExists, Note) ->
    case intervals:in(Key, ChangesInterval) andalso OldExists of
        true ->
            case length([K || K <- DeletedKeys, K =:= Key]) of
                1 -> ok;
                _ -> ?ct_fail("element(2, ?TEST_DB:get_changes(DB)) evaluated "
                              "to \"~w\" and did not contain 1x deleted key ~w~n(~s)~n",
                              [DeletedKeys, Key, lists:flatten(Note)])
            end;
        _    -> true
    end.

%% @doc Checks that an entry is present exactly once in the list of changed
%%      entries returned by ?TEST_DB:get_changes/1.
-spec check_entry_in_changed_entries(
        DB::?TEST_DB:db(), ChangesInterval::intervals:interval(), Entry::db_entry:entry(),
        {OldExists::boolean(), OldEntry::db_entry:entry()}, Note::string()) -> ok.
check_entry_in_changed_entries(DB, ChangesInterval, NewEntry, {_OldExists, OldEntry}, Note) ->
    {ChangedEntries, _DeletedKeys} = ?TEST_DB:get_changes(DB),
    check_entry_in_changed_entries_internal(ChangedEntries, ChangesInterval, NewEntry, OldEntry, Note).

-spec check_entry_in_changed_entries_internal(
        ChangedEntries::?TEST_DB:db_as_list(), ChangesInterval::intervals:interval(),
        NewEntry::db_entry:entry(), OldEntry::db_entry:entry(), Note::string()) -> ok.
check_entry_in_changed_entries_internal(ChangedEntries, ChangesInterval, NewEntry, OldEntry, Note) ->
    case intervals:in(db_entry:get_key(NewEntry), ChangesInterval) andalso
             OldEntry =/= NewEntry of
        true ->
            case length([E || E <- ChangedEntries, E =:= NewEntry]) of
                1 -> ok;
                _ -> ?ct_fail("element(1, ?TEST_DB:get_changes(DB)) evaluated "
                              "to \"~w\" and did not contain 1x changed entry ~w~n(~s)~n",
                              [ChangedEntries, NewEntry, lists:flatten(Note)])
            end;
        _    -> ok
    end.

%% @doc Checks that an entry is present exactly once in the list of changed
%%      entries returned by ?TEST_DB:get_changes/1.
-spec check_entry_in_changes(
        DB::?TEST_DB:db(), ChangesInterval::intervals:interval(), Entry::db_entry:entry(),
        {OldExists::boolean(), OldEntry::db_entry:entry()}, Note::string()) -> ok.
check_entry_in_changes(DB, ChangesInterval, NewEntry, {OldExists, OldEntry}, Note) ->
    {ChangedEntries, DeletedKeys} = ?TEST_DB:get_changes(DB),
    case db_entry:is_null(NewEntry) of
        true ->
            check_key_in_deleted_internal(DeletedKeys, ChangesInterval, db_entry:get_key(NewEntry), OldExists, Note);
        _ ->
            check_entry_in_changed_entries_internal(ChangedEntries, ChangesInterval, NewEntry, OldEntry, Note)
    end.

-spec count_keys_in_range(Keys::[?RT:key()], Interval::intervals:interval()) -> non_neg_integer().
count_keys_in_range(Keys, Interval) ->
    lists:foldl(fun(Key, Count) ->
                        case intervals:in(Key, Interval) of
                            true -> Count + 1;
                            _    -> Count
                        end
                end, 0, Keys).
