-module(jid_config).
-export([create/8]).
-export([port/1, jid/1, resource/1, status/1, password/1, room_confs/1, plugins/1, other_config/1]).

create(Port, Jid, Status, Resource, Password,
       RoomConfs, Plugins, OtherConfig) ->
    #{port => Port,
      jid => Jid,
      status => Status,
      resource => Resource,
      password => Password,
      room_confs => RoomConfs,
      plugins => Plugins,
      other => OtherConfig}.

port(State) ->
    maps:get(port, State).

jid(State) ->
    maps:get(jid, State).

resource(State) ->
    maps:get(resource, State).

status(State) ->
    maps:get(status, State).

password(State) ->
    maps:get(password, State).

room_confs(State) ->
    maps:get(room_confs, State).

plugins(State) ->
    maps:get(plugins, State).

other_config(State) ->
    maps:get(other, State).
