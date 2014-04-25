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

-module(ebunny).

-include("ebunny.hrl").

-behaviour(gen_server).

-define(SERVER, {local, ?MODULE}).

-define(EBUNNY_CONNECTION_PID, ebunny_connection_pid).
-define(EBUNNY_WORKER_TYPE_CONSUMER, ebunny_consumer_type).
-define(EBUNNY_WORKER_TYPE_PUBLISHER, ebunny_publisher_type).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([start_consumer/5, stop_consumer/1]).
-export([start_publisher/4, stop_publisher/1]).

start_link() ->
	gen_server:start_link(?SERVER, ?MODULE, [], []).

-spec start_consumer(WorkerName :: atom(), 
		Module :: atom(), 
		Args :: list(), 
		Host :: binary(), 
		Queue :: binary()) -> 
	ok | {error, Reason :: term()}.
start_consumer(WorkerName, Module, Args, Host, Queue) ->
	Worker = {?EBUNNY_WORKER_TYPE_CONSUMER, WorkerName},
	WorkerConfig = #consumer_record{consumer_name = WorkerName,
			host_uri = Host, 
			queue_name = Queue, 
			handler = Module,
			handler_args = Args},
	gen_server:call(?MODULE, {start, Worker, WorkerConfig}).

-spec stop_consumer(WorkerName :: atom()) -> ok.
stop_consumer(WorkerName) ->
	Worker = {?EBUNNY_WORKER_TYPE_CONSUMER, WorkerName},
	gen_server:cast(?MODULE, {stop, Worker}).

-spec start_publisher(WorkerName :: atom(), 
		Module :: atom(), 
		Args :: list(), 
		Host :: binary()) -> 
	ok | {error, Reason :: term()}.
start_publisher(WorkerName, Module, Args, Host) ->
	Worker = {?EBUNNY_WORKER_TYPE_PUBLISHER, WorkerName},
	WorkerConfig = #publisher_record{publisher_name = WorkerName,
			host_uri = Host, 
			handler = Module,
			handler_args = Args},
	gen_server:call(?MODULE, {start, Worker, WorkerConfig}).

-spec stop_publisher(WorkerName :: atom()) -> ok.
stop_publisher(WorkerName) ->
	Worker = {?EBUNNY_WORKER_TYPE_PUBLISHER, WorkerName},
	gen_server:cast(?MODULE, {stop, Worker}).

%% ====================================================================
%% Behavioural functions 
%% ====================================================================
-record(state, {pids, workers, hosts}).

-record(host, {connection, workers=[]}).

%% init
init([]) ->
	process_flag(trap_exit, true),	
	error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
	{ok, #state{pids=dict:new(), workers=dict:new(), hosts=dict:new()}}.

%% handle_call
handle_call({start, Worker, WorkerConfig}, _From, State) ->
	case dict:find(Worker, State#state.workers) of
		error ->
			case start(Worker, WorkerConfig, State) of
				{ok, NewState} ->
					{reply, ok, NewState};
				Other ->
					{reply, Other, State}
			end;
		{ok, _} -> {reply, {error, dublicated}, State}
	end.

%% handle_cast
handle_cast({stop, Worker}, State) ->
	NewState = stop(Worker, State),
	{noreply, NewState}.

%% handle_info
handle_info({'DOWN', _MonitorRef, process, Pid, Reason}, State=#state{pids=Pids}) ->
	case dict:find(Pid, Pids) of
		error -> {noreply, State};
		{ok, {?EBUNNY_CONNECTION_PID, Uri}} ->
			case dict:find(Uri, State#state.hosts) of
				error -> {noreply, State};
				{ok, Host} ->
					State1 = stop_workers(Host#host.workers, ?COMMAND_RESTART, State),
					NHosts = dict:erase(Uri, State1#state.hosts),
					NPids = dict:erase(Pid, Pids),
					{noreply, State1#state{hosts=NHosts, pids=NPids}}					
			end;
		{ok, Worker} ->
			case Reason of
				normal ->
					NewState = stop(Worker, State),
					{noreply, NewState};
				shutdown ->
					NewState = stop(Worker, State),
					{noreply, NewState};
				_ ->
					case dict:find(Worker, State#state.workers) of
						error -> {noreply, State};
						{ok, WorkerConfig} -> 
							NPids = dict:erase(Pid, Pids),
							case start(Worker, WorkerConfig, State#state{pids=NPids}) of
								{ok, NewState} ->
									{noreply, NewState};
								_ ->
									{noreply, State}
							end
					end
			end
	end.

%% terminate
terminate(_Reason, State=#state{workers=Workers}) ->
	dict:fold(fun(Worker, _Value, S) ->
				stop(Worker, S)
		end, State, Workers),
	ok.

%% code_change
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

get_host_uri(#consumer_record{host_uri=Uri}) -> Uri;
get_host_uri(#publisher_record{host_uri=Uri}) -> Uri.

start(Worker, WorkerConfig, State) ->
	Uri = get_host_uri(WorkerConfig),
	case get_connection(Uri, Worker, State) of
		{ok, Con, State1} ->
			case register_worker(Worker, WorkerConfig, State1) of
				{ok, State2} -> 
					case start_worker_server(Worker, Con, WorkerConfig) of
						{ok, Pid} ->
							erlang:monitor(process, Pid),
							NPids = dict:store(Pid, Worker, State2#state.pids),
							{ok, State2#state{pids=NPids}};
						Other -> Other
					end;
				Other -> Other
			end;
		Other -> Other
	end.

start_worker_server({?EBUNNY_WORKER_TYPE_CONSUMER, _WorkerName}, Connection, ConsumerConfig) ->
	eb_consumer_sup:start_consumer(Connection, ConsumerConfig);
start_worker_server({?EBUNNY_WORKER_TYPE_PUBLISHER, _WorkerName}, Connection, PublisherConfig) ->
	eb_publisher_sup:start_publisher(Connection, PublisherConfig).

register_worker(Worker, WorkerConfig, State) ->
	NWorkers = dict:store(Worker, WorkerConfig, State#state.workers),
	{ok, State#state{workers=NWorkers}}.

get_connection(Uri, Worker, State) ->
	case dict:find(Uri, State#state.hosts) of
		error ->
			case eb_api:connect(Uri) of
				{ok, Con} ->
					Host = append_worker(Worker, #host{connection=Con}),
					NHosts = dict:store(Uri, Host, State#state.hosts),
					NPids = dict:store(Con, {?EBUNNY_CONNECTION_PID, Uri}, State#state.pids),
					erlang:monitor(process, Con),
					{ok, Con, State#state{hosts=NHosts, pids=NPids}};
				{error, Reason} -> {error, Reason}
			end;
		{ok, Host} ->
			case eb_api:is_open(Host#host.connection) of
				true -> 
					NewHost = append_worker(Worker, Host),
					NHosts = dict:store(Uri, NewHost, State#state.hosts),
					{ok, Host#host.connection, State#state{hosts=NHosts}};
				false ->
					State1 = stop_workers(Host#host.workers, ?COMMAND_RESTART, State),
					NHosts = dict:erase(Uri, State1#state.hosts),
					get_connection(Uri, Worker, State1#state{hosts=NHosts})
			end
	end.

stop(Worker, State) ->
	stop_worker_server(Worker, ?COMMAND_TERMINATE, State),
	case unregister_worker(Worker, State) of
		not_found -> State;
		{WorkerConfig, State1} -> 
			Uri = get_host_uri(WorkerConfig),
			State2 = close_host(Uri, Worker, State1),
			case find_pid(Worker, State2#state.pids) of
				{ok, Pid} -> 
					NPids = dict:erase(Pid, State2#state.pids),
					State2#state{pids=NPids};
				error -> State2
			end
	end.

stop_workers([], _Command, State) -> State;
stop_workers([Worker|T], Command, State) ->
	State1 = stop_worker_server(Worker, Command, State),
	stop_workers(T, Command, State1).

stop_worker_server(Worker, Command, State) -> 
	case find_pid(Worker, State#state.pids) of
		{ok, Pid} -> 
			Pid ! Command,
			NPids = dict:erase(Pid, State#state.pids),
			State#state{pids=NPids};
		false -> State
	end.

find_pid(Worker, Dict) ->
	SelFun = fun(Key, Value, Acc) ->
			case Value =:= Worker of
				true -> [Key|Acc];
				false -> Acc
			end
	end,
	case dict:fold(SelFun, [], Dict) of
		[] -> false;
		[Pid|_] -> {ok, Pid}
	end.

append_worker(Worker, Host=#host{workers=List}) ->
	NewList = lists:delete(Worker, List),
	Host#host{workers=[Worker|NewList]}.

unregister_worker(Worker, State) ->
	case dict:find(Worker, State#state.workers) of
		error -> not_found;
		{ok, Config} -> 
			NWorkers = dict:erase(Worker, State#state.workers),
			{Config, State#state{workers=NWorkers}}
	end.

close_host(Uri, Worker, State) ->
	case dict:find(Uri, State#state.hosts) of
		error -> State;
		{ok, Host} ->
			NHost = remove_worker(Worker, Host),
			case NHost#host.workers of
				[] ->
					eb_api:disconnect(NHost#host.connection),
					NHosts = dict:erase(Uri, State#state.hosts),
					State#state{hosts=NHosts};
				_ ->
					NHosts = dict:store(Uri, NHost, State#state.hosts),
					State#state{hosts=NHosts}
			end
	end.

remove_worker(Worker, Host=#host{workers=List}) ->
	NewList = lists:delete(Worker, List),
	Host#host{workers=NewList}.