-module(chat_commands).
-behaviour(iris_plugin).

-export([start/3, process_message/2]).

-define(DEFAULT_COMMAND_PREFIX, "@").

start(_Parent, _Config, _From) ->
    okay.

process_message(Message, Config) ->
    Type = message:type(Message),
    case Type of 
        chat ->
            process_chat(Message, Config);
        groupchat ->
            preprocess_groupchat(Message, Config);
        error ->
            ulog:warning(?MODULE, "got XMPP error stanza: ~p", [message:raw(Message)]);
        _Other ->
            ulog:error(?MODULE, "got unknown message type: ~s", [Type])
    end.

process_chat(Message, Config) ->
    CommandList = proplists:get_value(commands, jid_config:other_config(Config)),
    lists:foreach(fun(Command) ->
                          Response = Command:run(string:tokens(message:body(Message), " "),
                                                 message:from(Message)),
                          ulog:debug("Command ~s returned ~p", [Command, Response]),
                          case Response of
                              nope -> ok;
                              _ -> Jid = exmpp_xml:get_attribute(message:raw(Message), <<"from">>, undefined),
                                   jid_worker:reply(Response, Jid)
                          end
                  end,
                  CommandList).

preprocess_groupchat(Message, Config) ->
    Stamp = exmpp_xml:get_element(message:raw(Message), delay), %% removing history messages
    case Stamp of
        undefined -> process_groupchat(Message, Config);
        _ -> ok
    end.

process_groupchat(Message, Config) ->
    RoomConfList = jid_config:room_confs(Config),
    FromRoom = message:from_room(Message),
    %% ulog:debug("Message from room ~s", [FromRoom]),
    [RoomConfig] = lists:filter(fun(RoomConf) ->
                                        room_config:jid(RoomConf) == FromRoom
                                end,
                                RoomConfList),
    CommandList = room_config:commands(RoomConfig),
    lists:foreach(fun(Command) ->
                          Response = Command:run(string:tokens(message:body(Message), " "),
                                                 message:from(Message)),
                          case Response of
                              nope -> ok;
                              _ -> From = exmpp_xml:get_attribute(message:raw(Message), <<"from">>, undefined),
                                   [RoomJid|NickResource] = string:tokens(misc:format_str("~s",[From]),"/"),
                                   Nick = string:join(NickResource, "/"), % In case nick/resource contains '/' characters
                                   NewMessage = Nick ++ ", " ++ Response,
                                   jid_worker:reply(NewMessage, RoomJid)
                          end
                  end,
                  CommandList).
