-module(core).
-behavior(gen_server).
-export([start_link/1]).
-export([init/1, code_change/3, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-include("xmpp.hrl").

-record(state,
        {supervisor
        }).

start_link(SupRef) ->
    State = #state{supervisor = SupRef},
    gen_server:start_link({local, core}, ?MODULE, State, []).

init(State) ->
    ok = application:ensure_started(exmpp),

    ok = application:ensure_started(crypto),
    ok = application:ensure_started(asn1),
    ok = application:ensure_started(public_key), 
    ok = application:ensure_started(ssl),
    ok = application:ensure_started(inets),

    SupervisorPid = State#state.supervisor,
    ulog:info("Core node started and has pid ~p, supervisor process is ~p", [self(), SupervisorPid]),

    %% Global config table, everyone can retrieve information from here
    %% calling core server with get_info request
    ConfigList = config:read(?DEFAULT_CONFIG_FILE),
    ets:new(config, [named_table, bag]),
    lists:foreach(fun(X) ->
                          ets:insert(config, X)
                  end,
                  ConfigList),
    ets:new(workers, [named_table, bag]),
    self() ! start_children,
    {ok, State}.

handle_call({get_config, Key}, _From, State) ->
    Reply = ets:lookup(config, Key),
    {reply, Reply, State};
handle_call(Any, _Caller, State) -> 
    ulog:info("Recieved unknown request: ~p", [Any]),
    {noreply, State}.

handle_cast({connected, From, Name}, State) ->
    ulog:info("Worker ~p has connected with pid ~p, starting plugins", [Name, From]),
    ets:insert(workers, {From, Name}),
    gen_server:cast(From, start_plugins),
    {noreply, State};
handle_cast({started_plugins, From, Name}, State) ->
    ulog:info("Worker ~p has connected plugins, joining rooms", [Name]),
    gen_server:cast(From, join_rooms),
    {noreply, State};
handle_cast({terminated, From, Reason}, State) ->
    [{_, Name}] = ets:lookup(workers, From),
    ulog:info("Worker ~p for jid ~p terminated.~nReason: ~p", [Name, From, Reason]),
    ets:delete_object(workers, {From, Name}),
    {noreply, State};
handle_cast(Any, State) ->
    ulog:info("Recieved unknown cast: '~p'", [Any]),
    {noreply, State}.

handle_info(start_children, State) ->
    ulog:info("Starting children"),
    Supervisor = State#state.supervisor,
    [{jids, JidConfigList}] = ets:lookup(config, jids),
    lists:foreach(fun(ConfigEntry) ->
                          ConfigMap = config:parse(jid_config, 
                                                   ConfigEntry),
                          start_worker(ConfigMap, Supervisor)
                  end,
                  JidConfigList),
    {noreply, State};
handle_info(_Msg, State) -> 
    ulog:info("Recieved unknown message: ~p~n", [_Msg]),
    {noreply, State}.

terminate(Reason, State) ->
    SupRef = State#state.supervisor,
    ets:foldl(fun(Elem, ok) ->
                      supervisor:terminate_child(SupRef, Elem),
                      supervisor:delete_child(SupRef, Elem),
                      ok
              end,
              ok,
              workers),
    ets:delete(workers),
    ulog:info("core process with pid ~p terminated. Reason: ~p",
              [self(), Reason]),
    ok.

code_change(_OldVersion, State, _Extra) -> {ok, State}.

%% gen_server callbacks end

start_worker(Config, Supervisor) ->
    Name = list_to_atom(jid_config:jid(Config)),
    ulog:info("Starting worker ~p with supervisor ~p", [Name, Supervisor]),
    {ok, _Pid} = supervisor:start_child(Supervisor,
                                        {Name,
                                         {jid_worker, start_link, [Config, Name, Supervisor]},
                                         transient,
                                         5000,
                                         worker,
                                         [jid_worker]}).
