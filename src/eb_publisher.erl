%%
%% Copyright 2014 Joaquim Rocha
%% 
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-module(eb_publisher).

-include("ebunny.hrl").

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/2]).
-export([call/2, cast/2]).

start_link(Connection, PublisherConfig) ->
	gen_server:start_link(?MODULE, [Connection, PublisherConfig], []).

-spec call(Server :: atom(), Msg :: term()) -> ok | {error, Reason :: term()}.
call(Server, Msg) ->
	gen_server:call(Server, {msg, Msg}).

-spec cast(Server :: atom(), Msg :: term()) -> ok.
cast(Server, Msg) ->
	gen_server:cast(Server, {msg, Msg}).

%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {publisher_name, channel, handler, handler_state}).

%% init
init([Connection, #publisher_record{publisher_name=ServerName, handler=Handler, handler_args=Args}]) ->
	error_logger:info_msg("Publisher ~p [~p] Starting...\n", [ServerName, self()]),
	case eb_api:open_channel(Connection) of
		{ok, Channel} ->
			{ok, HandlerState} = Handler:init(Args),
			erlang:register(ServerName, self()),
			State = #state{publisher_name=ServerName, 
					channel=Channel, 
					handler=Handler, 
					handler_state=HandlerState},
			{ok, State};
		{error, Reason} ->
			error_logger:error_msg("Publisher ~p: Error while trying to open channel: ~p\n", [ServerName, Reason])
	end.

%% handle_call
handle_call({msg, Msg}, _From, State) ->
	case msg(Msg, State) of
		{ok, State1} -> {reply, ok, State1};
		{error, Reason, State1} -> {reply, {error, Reason}, State1}
	end.

%% handle_cast
handle_cast({msg, Msg}, State) ->
	NewState = case msg(Msg, State) of
		{ok, State1} -> State1;
		{error, _Reason, State1} -> State1
	end,
	{noreply, NewState}.

%% handle_info
handle_info(?COMMAND_RESTART, State) ->
	{stop, ?COMMAND_RESTART, State};
handle_info(?COMMAND_TERMINATE, State) ->
	{stop, normal, State}.

%% terminate
terminate(_Reason, #state{channel=Channel}) ->
	eb_api:close_channel(Channel),
	ok.

%% code_change
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

msg(Msg, State=#state{channel=Channel, handler=Handler, handler_state=HandlerState}) ->
	case Handler:on_message(Msg, HandlerState) of
		{send, Exchange, RoutingKey, Payload, Persistent, NewState} ->
			case eb_api:send_message(Channel, Exchange, RoutingKey, Payload, Persistent) of
				ok -> {ok, State#state{handler_state=NewState}};
				{error, Reason} -> {error, Reason, State#state{handler_state=NewState}}
			end;
		{ignore, NewState} -> {ok, State#state{handler_state=NewState}}
	end.