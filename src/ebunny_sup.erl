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

-module(ebunny_sup).

-behaviour(supervisor).

-export([init/1]).
-export([start_link/0]).

start_link() ->
	supervisor:start_link(?MODULE, []).

init([]) ->
	EBUNNY = {ebunny, {ebunny, start_link, []}, permanent, infinity, worker, [ebunny]},
	EB_CONSUMER = {eb_consumer_sup, {eb_consumer_sup, start_link, []}, permanent, infinity, supervisor, [eb_consumer_sup]},
	EB_PUBLISHER = {eb_publisher_sup, {eb_publisher_sup, start_link, []}, permanent, infinity, supervisor, [eb_publisher_sup]},
	{ok, {{one_for_one, 5, 60}, [EBUNNY, EB_CONSUMER, EB_PUBLISHER]}}.


