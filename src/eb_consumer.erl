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

-module(eb_consumer).

-include("ebunny.hrl").

-record(state, {channel, subscription}).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/2, init/2]).

start_link(Connection, ConsumerConfig) ->
	Pid = spawn_link(?MODULE, init, [Connection, ConsumerConfig]),
	{ok, Pid}.

init(Connection, ConsumerConfig=#consumer_record{consumer_name=ServerName, handler=Handler, handler_args=Args}) ->
	error_logger:info_msg("Consumer ~p [~p] Starting...\n", [ServerName, self()]),
	case eb_api:open_channel(Connection) of
		{ok, Channel} ->
			io:format("~p - channel: ~p~n", [ServerName, Channel]),
			erlang:monitor(process, Channel),
			case eb_api:subscribe(Channel, ConsumerConfig#consumer_record.queue_name, self()) of
				{ok, Ref} ->
					State = #state{channel=Channel, subscription=Ref},
					{ok, HandlerState} = Handler:init(Args),
					loop(ConsumerConfig, State, HandlerState);
				{error, Reason} ->
					error_logger:error_msg("Consumer ~p: Error while subscribing ~s: ~p\n", [ServerName, ConsumerConfig#consumer_record.queue_name, Reason])
			end;
		{error, Reason} ->
			error_logger:error_msg("Consumer ~p: Error while trying to open channel: ~p\n", [ServerName, Reason])
	end.	

%% ====================================================================
%% Internal functions
%% ====================================================================

loop(ConsumerConfig=#consumer_record{handler=Handler}, State=#state{channel=Channel}, HandlerState) ->
	case eb_api:listen() of		
		{first, Ref} -> 
			loop(ConsumerConfig, State#state{subscription=Ref}, HandlerState);
		{last} -> 
			stop(Channel, Handler, HandlerState);
		{message, Value, MessageTag} -> 
			case Handler:on_message(Value, HandlerState) of
				{ack, NewState} ->
					eb_api:ack_message(Channel, MessageTag),
					loop(ConsumerConfig, State, NewState);
				{no_ack, NewState} -> 
					loop(ConsumerConfig, State, NewState)
			end;
		{other, Other} ->
			case Other of
				{'DOWN', _MonitorRef, process, Channel, _Reason} ->
					Handler:terminate(HandlerState),
					exit(channel_closed);
				{terminate} ->
					eb_api:unsubscribe(Channel, State#state.subscription),
					stop(Channel, Handler, HandlerState);
				Other ->
					error_logger:warning_msg("Consumer ~p: Receive ~p\n", [ConsumerConfig#consumer_record.consumer_name, Other]),
					loop(ConsumerConfig, State, HandlerState)
			end
	end.

stop(Channel, Handler, HandlerState) ->
	Handler:terminate(HandlerState),
	eb_api:close_channel(Channel).