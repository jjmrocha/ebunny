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

-module(eb_api).

-include_lib("amqp_client/include/amqp_client.hrl").

-define(DEFAULT_EXCHANGE, <<"">>).

%% ====================================================================
%% API functions
%% ====================================================================
-export([connect/0, connect/1, disconnect/1, is_open/1]).
-export([open_channel/1, close_channel/1]).
-export([create_queue/1, create_queue/4, delete_queue/2]).
-export([send_message/3, send_message/4, send_message/5]).
-export([get_message/2, get_message/3, ack_message/2]).
-export([subscribe/3, listen/0, unsubscribe/2]).

-spec connect() -> {ok, Connection :: pid()} | {error, Error :: term()}.
connect() ->
	open_connection(#amqp_params_network{}).

-spec connect(Uri :: string() | binary()) -> {ok, Connection :: pid()} | {error, Error :: term()}.
connect(Uri) when is_binary(Uri) ->
	connect(binary_to_list(Uri));
connect(Uri) ->
	case amqp_uri:parse(Uri) of
		{ok, Network} -> open_connection(Network);
		Other -> Other
	end.

-spec is_open(Con :: pid()) -> boolean().
is_open(Con) ->
	case erlang:is_process_alive(Con) of
		true ->
			Result = amqp_connection:info(Con, [is_closing]),
			case lists:keyfind(is_closing, 1, Result) of
				false -> false;
				{_, false} -> true;
				{_, true} -> false
			end;
		false -> false
	end.

-spec open_channel(Con :: pid()) -> {ok, Channel :: pid()} | {error, Error :: term()}.
open_channel(Con) ->
	amqp_connection:open_channel(Con).

-spec create_queue(Channel :: pid(), Queue :: binary(), Durable :: boolean(), AutoDelete :: boolean()) -> 
	ok | {error, Error :: term()}.
create_queue(Channel, Queue, Durable, AutoDelete) ->
	Declare = #'queue.declare'{queue = Queue, 
			durable = Durable, 
			auto_delete = AutoDelete},
	case amqp_channel:call(Channel, Declare) of
		#'queue.declare_ok'{} -> ok;
		ok -> ok;
		Other -> {error, Other}
	end.

-spec create_queue(Channel :: pid()) -> {ok, Queue :: binary()} | {error, Error :: term()}.
create_queue(Channel) ->
	Declare = #'queue.declare'{auto_delete = true},
	case amqp_channel:call(Channel, Declare) of
		#'queue.declare_ok'{queue = Queue} -> {ok, Queue};
		Other -> {error, Other}
	end.

-spec delete_queue(Channel :: pid(), Queue :: binary()) -> ok | {error, Error :: term()}.
delete_queue(Channel, Queue) ->
	Delete = #'queue.delete'{queue = Queue},
	case amqp_channel:call(Channel, Delete) of
		#'queue.delete_ok'{} -> ok;
		ok -> ok;
		Other -> {error, Other}
	end.

-spec send_message(Channel :: pid(), Exchange :: binary(), RoutingKey :: binary(), Msg :: binary(), Persistent :: boolean()) -> ok | {error, Error :: term()}.
send_message(Channel, Exchange, RoutingKey, Payload, Persistent) ->
	Publish = #'basic.publish'{exchange=Exchange, routing_key = RoutingKey},
	Props = case Persistent of
		true -> #'P_basic'{delivery_mode = 2};
		false -> #'P_basic'{}
	end,
	Msg = #amqp_msg{props = Props, payload = Payload},
	case amqp_channel:call(Channel, Publish, Msg) of
		ok -> ok;
		Other -> {error, Other}		
	end.

-spec send_message(Channel :: pid(), RoutingKey :: binary(), Msg :: binary(), Persistent :: boolean()) -> ok | {error, Error :: term()}.
send_message(Channel, RoutingKey, Payload, Persistent) ->
	send_message(Channel, ?DEFAULT_EXCHANGE, RoutingKey, Payload, Persistent).

-spec send_message(Channel :: pid(), RoutingKey :: binary(), Msg :: binary()) -> ok | {error, Error :: term()}.
send_message(Channel, RoutingKey, Payload) ->
	send_message(Channel, ?DEFAULT_EXCHANGE, RoutingKey, Payload, false).

-spec get_message(Channel :: pid(), Queue :: binary(), AutoAck :: boolean()) -> 
	{ok, Value :: term(), MessageTag :: term()} | empty | {error, Reason :: term()}.
get_message(Channel, Queue, AutoAck) ->
	Get = #'basic.get'{queue = Queue, no_ack = AutoAck},
	case amqp_channel:call(Channel, Get) of
		{#'basic.get_ok'{delivery_tag = Tag}, Content} ->
			#amqp_msg{payload = Payload} = Content,
			{ok, Payload, Tag};
		#'basic.get_empty'{} -> empty;
		Other -> {error, Other}
	end.

-spec get_message(Channel :: pid(), Queue :: binary()) -> {ok, Value :: term()} | empty | {error, Reason :: term()}.
get_message(Channel, Queue) ->
	case get_message(Channel, Queue, true) of
		{ok, Payload, _Tag} -> {ok, Payload};
		Other -> Other
	end.

-spec ack_message(Channel :: pid(), MessageTag :: term()) -> ok.
ack_message(Channel, MessageTag) ->
	amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = MessageTag}).

-spec subscribe(Channel :: pid(), Queue :: binary(), Pid :: pid()) -> 
	{ok, Ref :: term()} | {error, Reason :: term()}.
subscribe(Channel, Queue, Pid) ->
	Sub = #'basic.consume'{queue = Queue},
	case amqp_channel:subscribe(Channel, Sub, Pid) of
		#'basic.consume_ok'{consumer_tag = Ref} -> {ok, Ref};
		Other -> {error, Other}
	end.

-spec listen() -> 
	{first, Ref :: term()} | 
	{last} | 
	{message, Value :: term(), MessageTag :: term()} | 
	{other, Other :: any()}.
listen() ->
	receive
		#'basic.consume_ok'{consumer_tag = Ref} -> {first, Ref};		
		{#'basic.deliver'{delivery_tag = Tag}, Content} ->
			#amqp_msg{payload = Payload} = Content,
			{message, Payload, Tag};		
		#'basic.cancel_ok'{} -> {last};
		Other -> {other, Other}
	end.

-spec unsubscribe(Channel :: pid(), Ref :: term()) -> ok | {error, Reason :: term()}.
unsubscribe(Channel, Ref) ->
	if_running(Channel, fun() -> 
			amqp_channel:call(Channel, #'basic.cancel'{consumer_tag = Ref}),
			ok
		end).

-spec close_channel(Channel :: pid()) -> ok | {error, Reason :: term()}.
close_channel(Channel) ->
	if_running(Channel, fun() -> 
			amqp_channel:close(Channel)
		end).	

-spec disconnect(Connection :: pid()) -> ok | {error, Reason :: term()}.
disconnect(Connection) ->
	if_running(Connection, fun() -> 
			amqp_connection:close(Connection)
		end).

%% ====================================================================
%% Internal functions
%% ====================================================================

open_connection(Network) ->
	amqp_connection:start(Network).

if_running(Pid, Fun) ->
	case erlang:is_process_alive(Pid) of
		true -> Fun();
		false -> {error, not_running}
	end.