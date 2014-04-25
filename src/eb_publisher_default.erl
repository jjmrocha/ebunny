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

-module(eb_publisher_default).

-behaviour(eb_publisher_handler).

-define(EXCHANGE_KEY, exchange).
-define(ROUTING_KEY, default_routing_key).
-define(PERSISTENT_KEY, persistent).

-define(DEFAULT_EXCHANGE, <<"">>).

-export([init/1, on_message/2, terminate/1]).
-export([send/2, send/3]).

%% ====================================================================
%% Behaviour functions
%% ====================================================================

init(Args) ->
	Exchange = proplists:get_value(?EXCHANGE_KEY, Args, ?DEFAULT_EXCHANGE),
	DefaultRoutingKey = proplists:get_value(?ROUTING_KEY, Args),
	Persistent = proplists:get_value(?PERSISTENT_KEY, Args, false),
	{ok, {Exchange, DefaultRoutingKey, Persistent}}. 

on_message({RoutingKey, Msg}, State={Exchange, _DefaultRoutingKey, Persistent}) ->
	{send, Exchange, RoutingKey, Msg, Persistent, State};
on_message(Msg, State={_Exchange, undefined, _Persistent}) ->
	error_logger:warning_msg("~p: No RoutingKey for msg: ~p\n", [?MODULE, Msg]),
	{ignore, State};
on_message(Msg, State={Exchange, DefaultRoutingKey, Persistent}) ->
	{send, Exchange, DefaultRoutingKey, Msg, Persistent, State}.

terminate(_State) -> 
	ok.

%% ====================================================================
%% Client functions
%% ====================================================================

-spec send(PublisherName :: atom(), Msg :: binary()) -> ok.
send(PublisherName, Msg) ->
	eb_publisher:cast(PublisherName, Msg).

-spec send(PublisherName :: atom(), RoutingKey :: binary(), Msg :: binary()) -> ok.
send(PublisherName, RoutingKey, Msg) ->
	eb_publisher:cast(PublisherName, {RoutingKey, Msg}).