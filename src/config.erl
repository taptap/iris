-module(config).
-export([init/1, get_room_list/1, parse/2]).

-include_lib("exmpp/include/exmpp_client.hrl").
-include("xmpp.hrl").

init(Filename) ->
    {ok, [ConfigList]} = file:consult(Filename),
    ulog:info("Read configuration file ~s", [Filename]),
    ConfigList.

parse(jid_config, {jid_config, Config}) ->
    %% Debug only
    {_, Resource} = init:script_id(),
    #jid_info {
       jid = proplists:get_value(jid, Config),
       %% resource = proplists:get_value(resource, Config),
       resource = Resource,
       status = proplists:get_value(status, Config),
       password = proplists:get_value(password, Config),
       rooms = proplists:get_value(rooms, Config),
       modules = proplists:get_value(modules, Config)
      }.

get_room_list(#jid_info{rooms = RoomList}) ->
    lists:map(
      fun(RoomTuple) ->
	      if tuple_size(RoomTuple) == 2 ->
		      {Room, Nick} = RoomTuple,
		      {Room, Nick, nopassword};
		 tuple_size(RoomTuple) == 3 ->
		      {Room, Nick, Password} = RoomTuple,
		      {Room, Nick, Password};
		 true -> 
		      ulog:error("Bad Room Tuple ~p", [RoomTuple]),
		      error
	      end
      end,
      RoomList).
	      
	      
	  
			  
