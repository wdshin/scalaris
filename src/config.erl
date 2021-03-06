%  @copyright 2007-2012 Zuse Institute Berlin

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

%% @author Thorsten Schuett <schuett@zib.de>
%% @doc    Config file parser for scalaris.
%% @end
%% @version $Id$
-module(config).
-author('schuett@zib.de').
-vsn('$Id$').
-include("scalaris.hrl").

-export([
         start_link/1, start_link/2, init/2,
         read/1, write/2,
         check_config/0,

         cfg_exists/1, cfg_is_atom/1, cfg_is_bool/1, cfg_is_mypid/1,
         cfg_is_ip/1, cfg_is_ip/2, cfg_is_port/1,
         cfg_is_integer/1, cfg_is_float/1,
         cfg_is_tuple/2, cfg_is_tuple/4, cfg_is_list/1, cfg_is_list/3, cfg_is_string/1,
         cfg_is_in_range/3, cfg_is_greater_than/2, cfg_is_greater_than_equal/2,
         cfg_is_less_than/2, cfg_is_less_than_equal/2, cfg_is_in/2, cfg_is_module/1,
         cfg_test_and_error/3,

         system_continue/3,
         system_code_change/4,
         system_terminate/4,
         loop/0
        ]).

%% public functions

%% @doc Reads a config parameter. If it is not found, the application's
%%      environment is checked or failed is returned. The result will be
%%      cached in the config.
-spec read(Key::atom()) -> any() | failed.
read(Key) ->
    % If an environment variable sets a config parameter that is present in the
    % config, it will override the config (see populate_db/1, process_term/1).
    % We can thus first check the ets table and fall back to the environment
    % check afterwards.
    case ets:info(config_ets) of
        undefined ->
            io:format("config not started yet (trying to read ~p)\n", [Key]),
            failed;
        _ ->
            case ets:lookup(config_ets, Key) of
                [{Key, Value}] -> Value;
                [] -> Value = util:app_get_env(Key, failed),
                      case Value of
                          failed -> ok;
                          _ -> case self() =:= erlang:whereis(config) of
                                   true -> ets:insert(config_ets, {Key, Value});
                                   _    -> write(Key, Value)
                               end
                      end,
                      Value
            end
    end.

%% @doc Writes a config parameter.
-spec write(atom(), any()) -> ok.
write(Key, Value) ->
    comm:send_local(config, {write, self(), Key, Value}),
    receive
        {write_done} -> ok
    end.

%% gen_server setup

%% @doc Starts the config process and determines the config files from
%%      the application's environment. If there is no application,
%%      "scalaris.cfg" and "scalaris.local.cfg" are used. If Options
%%      contains a {config, [{Key1, Value1},...]} tuple, each Key is
%%      set to its Value in the config.
-spec start_link(Options::[tuple()]) -> {ok, pid()}.
start_link(Options) ->
    Files = [util:app_get_env(config, "scalaris.cfg"),
             util:app_get_env(local_config, "scalaris.local.cfg")],
    start_link(Files, Options).

%% @doc Starts the config process. If Options contains a {config,
%%      [{Key1, Value1},...]} tuple, each Key is set to its Value in
%%      the config.
-spec start_link(Filename::[file:name()], Options::[tuple()]) -> {ok, pid()}.
start_link(Files, Options) ->
    case whereis(config) of
        Pid when is_pid(Pid) ->
            %% ct:pal("There is already a Config process:~n"),
            {ok, Pid};
        _ ->
            TheFiles = case util:app_get_env(add_config, []) of
                           []         -> Files;
                           ConfigFile -> lists:append(Files, [ConfigFile])
                       end,
%%             error_logger:info_msg("Config files: ~p~n", [TheFiles]),
            Owner = self(),
            Link = spawn_link(?MODULE, init, [TheFiles, Owner]),
            receive
                done -> ok;
                X    -> error_logger:error_msg("unknown config message  ~p", [X])
            end,
            ConfigParameters = case lists:keyfind(config, 1, Options) of
                                   {config, ConfPars} -> ConfPars;
                                   _ -> []
                               end,
            _ = [write(K, V) || {K, V} <- ConfigParameters],
            {ok, Link}
    end.

%@private
-spec init(Files::[file:name()], Owner::pid()) -> no_return().
init(Files, Owner) ->
    erlang:register(config, self()),
    _ = ets:new(config_ets, [set, protected, named_table]),
    _ = [ populate_db(File) || File <- Files],
    try check_config() of
        true -> ok;
        _    -> % wait so the error output can be written:
            init:stop(1),
            receive nothing -> ok end
    catch Err:Reason -> % wait so the error output can be written:
            error_logger:error_msg("check_config/0 crashed with: ~.0p:~.0p~nStacktrace:~p~n",
                                   [Err, Reason, erlang:get_stacktrace()]),
            init:stop(1),
            receive nothing -> ok end
    end,
    Owner ! done,
    loop().

-spec loop() -> no_return().
loop() ->
    receive
        {write, Pid, Key, Value} ->
            ets:insert(config_ets, {Key, Value}),
            comm:send_local(Pid, {write_done}),
            loop();
        %% handle sys:suspend messages
        {system, From, Msg} ->
            sys:handle_system_msg(Msg, From, self(), config, [], no_state);
        _ ->
            loop()
    end.

-spec system_continue(any(), any(), any()) -> none().
system_continue(_, _, _) ->
    %% need a full qualified function call to change to new code
    config:loop().
-spec system_code_change(any(), config, any(), any()) -> {ok, no_state}.
system_code_change(_State, ?MODULE, _OldVsn, _Extra) ->
    {ok, no_state}.
-spec system_terminate(any(), any(), any(), any()) -> ok.
system_terminate(_Reason, _Parent, _Debug, _State) ->
    ok.

%@private
-spec populate_db(File::file:name()) -> ok | fail.
populate_db([]) -> ok;
populate_db(File) ->
    %% note: log4erl may not be available -> use error_logger instead of log
    case file:consult(File) of
        {ok, Terms} ->
            _ = lists:map(fun process_term/1, Terms),
            ok;
        {error, enoent} ->
            case File =/= "scalaris.local.cfg" of
                true ->
                    error_logger:info_msg(
                      "Can't load config file ~p: File does not exist. "
                      " Ignoring.\n", [File]);
                false -> ok
            end,
            fail;
        {error, Reason} ->
            error_logger:error_msg("Can't load config file ~p: ~p. Exiting.\n",
                                   [File, Reason]),
            init:stop(1),
            receive nothing -> ok end
            %fail
    end.

-spec process_term({Key::atom(), Value::term()}) -> true.
process_term({Key, Value}) ->
    ets:insert(config_ets, {Key, util:app_get_env(Key, Value)}).

%% check config methods

%% @doc Checks whether config parameters of all processes exist and are valid.
-spec check_config() -> boolean().
check_config() ->
    Checks =
        [ case X() of
              true -> true;
              false ->
                  ct:pal(error, "check_config ~p failed.~n", [X]),
                  false
          end || X  <- [ fun log:check_config/0,
                         fun sup_scalaris:check_config/0,
                         fun sup_dht_node_core:check_config/0,
                         fun cyclon:check_config/0,
                         fun acceptor:check_config/0,
                         fun gossip:check_config/0,
                         fun learner:check_config/0,
                         fun rdht_tx:check_config/0,
                         fun rdht_tx_read:check_config/0,
                         fun rdht_tx_write:check_config/0,
                         fun ?RT:check_config/0,
                         fun rt_loop:check_config/0,
                         fun tx_tm_rtm:check_config/0,
                         fun vivaldi:check_config/0,
                         fun vivaldi_latency:check_config/0,
                         fun ?RM:check_config/0,
                         fun fd_hbs:check_config/0,
                         fun dht_node_move:check_config/0,
                         fun dht_node_join:check_config/0,
                         %% note: need to check all passive load
                         %%       balancing algorithm's parameters
                         %%       (another node may ask us to provide
                         %%       a candidate for any of them)
                         fun lb_psv_simple:check_config/0,
                         fun lb_psv_split:check_config/0,
                         fun lb_psv_gossip:check_config/0,
                         fun comm_acceptor:check_config/0,
                         fun monitor:check_config/0,
                         fun monitor_perf:check_config/0,
                         fun rrd:check_config/0,
                         fun rrepair:check_config/0,
                         fun sup_yaws:check_config/0 ]],
    lists:foldl(fun(A,B) -> A and B end, true, Checks).

-spec cfg_exists(Key::atom()) -> boolean().
cfg_exists(Key) ->
    case read(Key) of
        failed ->
            error_logger:error_msg("~p not defined (see scalaris.cfg and scalaris.local.cfg)~n", [Key]),
            false;
        _X -> true
    end.

%% @doc Tests the config parameter stored under atom Key with function Pred and
%%      prints an error message if not, also returns the result.
-spec cfg_test_and_error(Key::atom(), Pred::fun((any()) -> boolean()), Msg::list()) -> boolean().
cfg_test_and_error(Key, Pred, Msg) ->
    Value = read(Key),
    case cfg_exists(Key) andalso Pred(Value) of
        true -> true;
        false -> error_logger:error_msg("~p = ~p ~s (see scalaris.cfg and scalaris.local.cfg)~n",
                                            [Key, Value, lists:flatten(Msg)]),
                 false
    end.

-spec cfg_is_atom(Key::atom()) -> boolean().
cfg_is_atom(Key) ->
    Pred = fun erlang:is_atom/1,
    Msg = "is not an atom",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_module(Key::atom()) -> boolean().
cfg_is_module(Key) ->
    Pred = fun(Value) ->
                   erlang:is_atom(Value) andalso
                       code:which(Value) =/= non_existing
           end,
    Msg = "is not an existing module",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_bool(Key::atom()) -> boolean().
cfg_is_bool(Key) ->
    Pred = fun erlang:is_boolean/1,
    Msg = "is not a boolean",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_mypid(Key::atom()) -> boolean().
cfg_is_mypid(Key) ->
    Pred = fun comm:is_valid/1,
    Msg = "is not a valid pid",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_ip(Key::atom()) -> boolean().
cfg_is_ip(Key) ->
    cfg_is_ip(Key, false).

-spec cfg_is_ip(Key::atom(), AllowUnknown::boolean()) -> boolean().
cfg_is_ip(Key, AllowUnknown) ->
    IsIp = fun(Value) ->
                   case Value of
                       {IP1, IP2, IP3, IP4} ->
                           ((IP1 >= 0) andalso (IP1 =< 255)
                            andalso (IP2 >= 0) andalso (IP2 =< 255)
                            andalso (IP3 >= 0) andalso (IP3 =< 255)
                            andalso (IP4 >= 0) andalso (IP4 =< 255));
                       unknown when AllowUnknown -> true;
                       _X -> false
                   end
           end,
    Msg = "is not a valid IPv4 address",
    cfg_test_and_error(Key, IsIp, Msg).

-spec cfg_is_port(Key::atom()) -> boolean().
cfg_is_port(Key) ->
    IsPort = fun(Value) ->
                     case Value of
                         X when erlang:is_integer(X) ->
                             true;
                         Y when erlang:is_list(Y) ->
                             lists:all(fun erlang:is_integer/1, Y);
                         {From, To} ->
                             erlang:is_integer(From) andalso
                                 erlang:is_integer(To);
                         _ -> false
                     end
             end,
    Msg = "is not a valid Port address",
    cfg_test_and_error(Key, IsPort, Msg).

-spec cfg_is_integer(Key::atom()) -> boolean().
cfg_is_integer(Key) ->
    Pred = fun erlang:is_integer/1,
    Msg = "is not a valid integer",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_float(Key::atom()) -> boolean().
cfg_is_float(Key) ->
    Pred = fun erlang:is_float/1,
    Msg = "is not a valid float",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_tuple(Key::atom(), TupleSize::pos_integer()) -> boolean().
cfg_is_tuple(Key, Size) ->
    Pred = fun(Value) ->
                   erlang:is_tuple(Value) andalso
                       (erlang:tuple_size(Value) =:= Size)
           end,
    Msg = io_lib:format("is not a valid tuple of size ~p", [Size]),
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_tuple(Key::atom(), TupleSize::pos_integer(), Pred::fun((any()) -> boolean()), PredDescr::string()) -> boolean().
cfg_is_tuple(Key, Size, Pred, PredDescr) ->
    CompletePred = fun(Value) ->
                           erlang:is_tuple(Value) andalso
                               (erlang:tuple_size(Value) =:= Size) and
                               Pred(Value)
                   end,
    Msg = io_lib:format("is not a valid tuple of size ~p satisfying ~p", [Size, PredDescr]),
    cfg_test_and_error(Key, CompletePred, Msg).

-spec cfg_is_list(Key::atom()) -> boolean().
cfg_is_list(Key) ->
    Pred = fun erlang:is_list/1,
    Msg = "is not a valid list",
    cfg_test_and_error(Key, Pred, Msg).

-spec cfg_is_list(Key::atom(), Pred::fun((any()) -> boolean()), PredDescr::string()) -> boolean().
cfg_is_list(Key, Pred, PredDescr) ->
    IsListWithPred = fun(Value) ->
                             case Value of
                                 X when erlang:is_list(X) ->
                                     lists:all(Pred, X);
                                 _X -> false
                             end
                     end,
    Msg = io_lib:format("is not a valid list with elements satisfying ~p", [PredDescr]),
    cfg_test_and_error(Key, IsListWithPred, Msg).

-spec cfg_is_string(Key::atom()) -> boolean().
cfg_is_string(Key) ->
    IsChar = fun(X) -> (X >= 0) andalso (X =< 255) end,
    IsString = fun(Value) ->
                   case Value of
                       X when erlang:is_list(X) ->
                           lists:all(IsChar, X);
                       _X -> false
                   end
           end,
    Msg = "is not a (printable) string",
    cfg_test_and_error(Key, IsString, Msg).

-spec cfg_is_in_range(Key::atom(), Min::number(), Max::number()) -> boolean().
cfg_is_in_range(Key, Min, Max) ->
    IsInRange = fun(Value) -> (Value >= Min) andalso (Value =< Max) end,
    Msg = io_lib:format("is not between ~p and ~p (both inclusive)",
                        [Min, Max]),
    cfg_test_and_error(Key, IsInRange, Msg).

-spec cfg_is_greater_than(Key::atom(), Min::number() | atom()) -> boolean().
cfg_is_greater_than(_Key, failed) -> false; %% stop endless loop
cfg_is_greater_than(Key, Min) when erlang:is_atom(Min) ->
    cfg_is_greater_than(Key, read(Min));
cfg_is_greater_than(Key, Min) ->
    IsGreaterThan = fun(Value) -> (Value > Min) end,
    Msg = io_lib:format("is not larger than ~p", [Min]),
    cfg_test_and_error(Key, IsGreaterThan, Msg).

-spec cfg_is_greater_than_equal(Key::atom(), Min::number() | atom()) -> boolean().
cfg_is_greater_than_equal(_Key, failed) -> false; %% stop endless loop
cfg_is_greater_than_equal(Key, Min) when erlang:is_atom(Min) ->
    cfg_is_greater_than_equal(Key, read(Min));
cfg_is_greater_than_equal(Key, Min) ->
    IsGreaterThanEqual = fun(Value) -> (Value >= Min) end,
    Msg = io_lib:format("is not larger than or equal to ~p", [Min]),
    cfg_test_and_error(Key, IsGreaterThanEqual, Msg).

-spec cfg_is_less_than(Key::atom(), Max::number() | atom()) -> boolean().
cfg_is_less_than(_Key, failed) -> false; %% stop endless loop
cfg_is_less_than(Key, Max) when erlang:is_atom(Max) ->
    cfg_is_less_than(Key, read(Max));
cfg_is_less_than(Key, Max) ->
    IsLessThan = fun(Value) -> (Value < Max) end,
    Msg = io_lib:format("is not less than ~p", [Max]),
    cfg_test_and_error(Key, IsLessThan, Msg).

-spec cfg_is_less_than_equal(Key::atom(), Max::number() | atom()) -> boolean().
cfg_is_less_than_equal(_Key, failed) -> false; %% stop endless loop
cfg_is_less_than_equal(Key, Max) when erlang:is_atom(Max) ->
    cfg_is_less_than_equal(Key, read(Max));
cfg_is_less_than_equal(Key, Max) ->
    IsLessThanEqual = fun(Value) -> (Value =< Max) end,
    Msg = io_lib:format("is not less than or equal to ~p", [Max]),
    cfg_test_and_error(Key, IsLessThanEqual, Msg).

-spec cfg_is_in(Key::atom(), ValidValues::[any(),...]) -> boolean().
cfg_is_in(Key, ValidValues) ->
    IsIn = fun(Value) -> lists:any(fun(X) -> X =:= Value end,
                                   ValidValues) end,
    Msg = io_lib:format("is not allowed (valid values: ~p)",
                        [ValidValues]),
    cfg_test_and_error(Key, IsIn, Msg).
