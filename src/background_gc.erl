%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2017 Pivotal Software, Inc.  All rights reserved.
%%

-module(background_gc).

-behaviour(gen_server2).

-export([start_link/0, run/0]).
-export([gc/0]). %% For run_interval only

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(MAX_RATIO, 0.01).
-define(MAX_INTERVAL, 240000).

-record(state, {last_interval}).

%%----------------------------------------------------------------------------

-spec start_link() -> {'ok', pid()} | {'error', any()}.
-spec run() -> 'ok'.
-spec gc() -> 'ok'.

%%----------------------------------------------------------------------------

start_link() -> gen_server2:start_link({local, ?MODULE}, ?MODULE, [],
                                       [{timeout, infinity}]).

run() -> gen_server2:cast(?MODULE, run).

%%----------------------------------------------------------------------------

init([]) ->
    {ok, IdealInterval} = application:get_env(rabbit, background_gc_target_interval),
    {ok, interval_gc(#state{last_interval = IdealInterval})}.

handle_call(Msg, _From, State) ->
    {stop, {unexpected_call, Msg}, {unexpected_call, Msg}, State}.

handle_cast(run, State) -> gc(), {noreply, State};

handle_cast(Msg, State) -> {stop, {unexpected_cast, Msg}, State}.

handle_info(run, State) -> {noreply, interval_gc(State)};

handle_info(Msg, State) -> {stop, {unexpected_info, Msg}, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_Reason, State) -> State.

%%----------------------------------------------------------------------------

interval_gc(State = #state{last_interval = LastInterval}) ->
    {ok, IdealInterval} = application:get_env(rabbit, background_gc_target_interval),
    {ok, Interval} = rabbit_misc:interval_operation(
                       {?MODULE, gc, []},
                       ?MAX_RATIO, ?MAX_INTERVAL, IdealInterval, LastInterval),
    erlang:send_after(Interval, self(), run),
    State#state{last_interval = Interval}.

gc() ->
    Enabled = rabbit_misc:get_env(rabbit, background_gc_enabled, false),
    case Enabled of
        true ->
            [garbage_collect(P) || P <- processes(),
                                   {status, waiting} == process_info(P, status)],
            %% since we will never be waiting...
            garbage_collect();
         false ->
            ok
    end,
    ok.
