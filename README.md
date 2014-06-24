eBunny
======
*a simplifying wrapper for the rabbit-erlang-client*

1. Setup
--------

### 1.1. Installation ###

Using rebar:

```erlang
{deps, [
	{ebunny, ".*", {hg, "https://bitbucket.org/jjmrocha/ebunny", "default"}}
]}.
```

Download rabbit-erlang-client:

```
deps/ebunny/rabbit.sh
```

### 1.2. Start eBunny ###

```erlang
ok = application:start(ebunny).
```

2. Message consumers
--------------------

A message consumer is a module that implements the ```eb_consumer_handler``` behavior to receive automatically messages from a queue.

### 2.1. Write a module that implements the eb_consumer_handler behavior ###

The behavior has the following functions:

```erlang
init(Args :: list()) -> {ok, State :: term()}. 

on_message(Msg :: binary(), State :: term()) 
	-> {ack, State :: term()} | {no_ack, State :: term()}.

terminate(State :: term()) -> ok.
```

Where:

 - init/1 **eBunny will call this function to initialize the consumer**
 - on_message/2 **eBunny will call this function every time it retrieves a message from the queue, the function must answer with:**
     - ```{ack, State}``` - To acknowledge the message
     - ```{no_ack, State}``` - To receive the next message without sending an acknowledgement for last message
 - terminate/1 **eBunny will call this function before terminate consumer**

Example:

```erlang
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
```

### 2.2. Start a consumer ###

```erlang
ebunny:start_consumer(
    ConsumerName :: atom(), 
    Module :: atom(), 
    Args :: list(), 
    HostURI :: binary(), 
    QueueName :: binary()) -> ok | {error, Reason :: term()}.
```

Where:

 - ConsumerName **Identifies the consumer in subsequent interactions with eBuddy**
 - Module       **Module that implements the ```eb_consumer_handler``` behavior**
 - Args         **Arguments to pass to the function ```init()```**
 - HostURI      **AMQP URI for the message broker**
 - QueueName    **Name of the queue to listen on**

Example:

```erlang
Args = [],
URI = <<"amqp://127.0.0.1">>,
Queue = <<"testQueue">>,
ebunny:start_consumer(con, eb_consumer_debug, Args, URI, Queue).
```

3. Message publisher
--------------------

A message publisher is a module that implements the ```eb_publisher_handler``` behavior to convert and send messages to the message broker.

### 3.1. Write a module that implements the eb_publisher_handler behavior ###

The behavior has the following functions:

```erlang
init(Args :: list()) -> {ok, State :: term()}. 

on_message(InMsg :: term(), State :: term()) 
	-> {send, Exchange :: binary(), RoutingKey :: binary(), OutMsg :: binary(), Persistent :: boolean(), State :: term()} 
	| {ignore, State :: term()}.

terminate(State :: term()) -> ok.
```

Where:

 - init/1 **eBunny will call this function to initialize the publisher**
 - on_message/2 **eBunny will call this function every time it receives a message for the publisher, the function must answer with:**
     - ```{send, Exchange, RoutingKey, OutMsg, Persistent, State}``` - To send the message ```OutMsg``` for the exchange ```Exchange``` with the routing key ```RoutingKey```
     - ```{ignore, State}``` - If the publisher doesn't want to send a message in response to ```InMsg```
 - terminate/1 **eBunny will call this function before terminate publisher**

Example:

```erlang
-module(eb_publisher_example).

-behaviour(eb_publisher_handler).

-record(state, {key}).

-export([init/1, on_message/2, terminate/1]).

init(Args) ->
	RoutingKey = proplists:get_value(routing_key, Args),
	{ok, #state{key=RoutingKey}}. 

on_message(Msg, State=#state{key=RoutingKey}) ->
	{send, <<"">>, RoutingKey, Msg, false, State}.

terminate(_State) -> ok.
```

### 3.2. Start a publisher ###

```erlang
ebunny:start_publisher(
    PublisherName :: atom(), 
	Module :: atom(), 
	Args :: list(), 
	HostURI :: binary()) -> ok | {error, Reason :: term()}.
```

Where:

 - PublisherName **Identifies the publisher in subsequent interactions with eBuddy**
 - Module       **Module that implements the ```eb_publisher_handler``` behavior**
 - Args         **Arguments to pass to the function ```init()```**
 - HostURI      **AMQP URI for the message broker**

Example:

```erlang
Args = [{routing_key, <<"testQueue">>}],
URI = <<"amqp://127.0.0.1">>,
ebunny:start_publisher(pub, eb_publisher_example, Args, URI).
```

### 3.3. Send messages ###

To send messages to the publisher use eb_publisher module:

```erlang
eb_publisher:call(
    PublisherName :: atom(), 
    Msg :: term()) -> ok | {error, Reason :: term()}.

eb_publisher:cast(
    PublisherName :: atom(), 
    Msg :: term()) -> ok.
```

Example:

```erlang
eb_publisher:cast(pub, <<"Hello message">>).
```