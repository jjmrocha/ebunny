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

-module(eb_consumer_debug).

-behaviour(eb_consumer_handler).

-export([init/1, on_message/2, terminate/1]).

init(Args) ->
	error_logger:info_msg("init(~p)\n", [Args]),
	{ok, []}. 

on_message(Msg, State) ->
	error_logger:info_msg("on_message(~p)\n", [Msg]),
	{ack, State}.

terminate(_State) -> 
	error_logger:info_msg("terminate()\n"),
	ok.

%% ====================================================================
%% Internal functions
%% ====================================================================


