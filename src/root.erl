-module(root).
-behavior(gen_server).
-export([start_link/1]).
-export([init/1, code_change/3, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-include("xmpp.hrl").

-record(state,
	{supervisor
	}).

start_link(SupRef) ->
    State = #state{supervisor = SupRef},
    gen_server:start_link({local, root}, ?MODULE, State, []).

init(State) ->
    application:start(exmpp),

    application:start(crypto),
    application:start(public_key), 
    application:start(ssl),
    application:start(inets),


    SupervisorPid = State#state.supervisor,
    ulog:info("Root node started and has PID ~p, supervisor process is ~p", [self(), SupervisorPid]),

    %% Global config table, everyone can retrieve information from here
    %% Calling root server with get_info request
    ConfigList = config:init("priv/cfg.erl"),
    ets:new(config, [named_table, bag]),
    lists:foreach(fun(X) ->
			  ets:insert(config, X)
		  end,
		  ConfigList),
    %% Place to store children's states
    ets:new(workers, [named_table, bag]),
    self() ! connect_plugins,
    {ok, State}.

handle_call({get_config, Key}, _From, State) ->
    Reply = ets:lookup(config, Key),
    {reply, Reply, State};
handle_call({get_http, Query}, _From, State) ->
    try httpc:request(Query) of
	{ok, {{_Version, 200, _ReasonPhrase}, _Headers, Response}} ->
	    Response,
	    {reply, Response, State};
	Any ->
	    ulog:info("Request failed: ~p", [Any]),
	    {reply, error, State}
    catch
	error:Exception ->
	    ulog:info("Exception ~p occcured!", [Exception]),
	    {reply, error, State}
    end;
handle_call(Any, _Caller, State) -> 
    ulog:info("Recieved UNKNOWN request: ~p", [Any]),
    {noreply, State}.

handle_cast({connected, From, Name}, State) ->
    ulog:info("Worker ~p has connected with pid ~p, now entering rooms...~n", [Name, From]),
    ets:insert(workers, {From, Name}),
    gen_server:cast(From, join_rooms),
    {noreply, State};
handle_cast({terminated, From, Reason}, State) ->
    [{_, Name}] = ets:lookup(workers, From),
    ulog:info("Worker ~p for jid ~p terminated.~nReason: ~p", [Name, From, Reason]),
    ets:delete_object(workers, {From, Name}),
    {noreply, State};
handle_cast(Any, State) ->
    ulog:info("Recieved UNKNOWN cast: '~p'", [Any]),
    {noreply, State}.

handle_info(connect_plugins, State = #state{supervisor = Sup}) ->
    [{plugins, List}] = ets:lookup(config, plugins),
    lists:foreach(fun(Plugin) ->
			  start_plugin(Plugin, Sup)
		  end,
		  List),
    self() ! start_children,
    {noreply, State};
handle_info(start_children, State) ->
    ulog:info("Starting children"),

    Supervisor = State#state.supervisor,
    JidConfigList = ets:lookup(config, jid_config),
    lists:foreach(fun(ConfigEntry) ->
			  ConfigRecord = config:parse(jid_config, 
						      ConfigEntry),
			  start_worker(ConfigRecord, Supervisor)
		  end,
		  JidConfigList),
    {noreply, State};
handle_info(_Msg, State) -> 
    ulog:info("Recieved UNKNOWN message: ~p~n", [_Msg]),
    {noreply, State}.

terminate(_Reason, State) ->
    SupRef = State#state.supervisor,
    ets:foldl(fun(Elem, ok) ->
		      supervisor:terminate_child(SupRef, Elem),
		      supervisor:delete_child(SupRef, Elem),
		      ok
	      end,
	      ok,
	      workers),
    ets:delete(workers),
    ok.

code_change(_OldVersion, State, _Extra) -> {ok, State}.

%% gen_server callbacks end

start_worker(Config, Supervisor) ->
    Name = list_to_atom(Config#jid_info.jid),
    ulog:info("Starting worker ~p with supervisor ~p", [Name, Supervisor]),
    {ok, _Pid} = supervisor:start_child(Supervisor,
					{Name,
					 {jid_worker, start_link, [Config, Name]},
					 transient,
					 5000,
					 worker,
					 [jid_worker]}).

start_plugin(Plugin, Supervisor) ->
    try Plugin:start(Supervisor) of
	{ok, Pid} ->
	    ulog:info("~p started with pid ~p", [Plugin, Pid]),
	    ok
    catch
	error:Exception ->
	    ulog:info("Plugin ~p failed to load with exception:~n~p~n"
		      "Backtrace: ~p", [Plugin, Exception, erlang:get_stacktrace()])
    end.
	
