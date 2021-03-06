-module(url_title).
-behaviour(iris_plugin).

-export([start/3, process_message/2, stop/1]).

start(_Supervisor, _WorkerConfig, _From) ->
    ok.

process_message(Message, Config) ->
    Type = message:type(Message),
    case Type of
        groupchat ->
            case message:is_history(Message) of
                false -> process_groupchat(Message, Config);
                true -> ok
            end;
        error ->
            lager:warning("got XMPP error stanza: ~p", [message:raw(Message)]);
        _Other ->
            lager:error("got unknown message type: ~s", [Type])
    end.

stop(_From) ->
    ok.

process_groupchat(Message, Config) ->
    FromRoom = message:from_room(Message),
    BotName = jid_worker:get_config(self(), FromRoom, nick),
    Nick = message:nick(Message),
    if Nick /= BotName ->
            process_text(Message, Config);
       true ->
            ok
    end.

process_text(Message, _Config) ->
    Match = re:run(message:body(Message), "((https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})(\/(?:[\/\w\.-]*)*\/?)?([\/?#][^ ]*))", [{capture, [1]}]),
    case Match of
        nomatch    -> ok;
        {match, [{Start,Length}]} ->
            lager:debug("[~s] matched ~p [~s]", [?MODULE, {Start, Length}, message:body(Message)]),
            URL = string:substr(message:body(Message), Start+1,Length),
            Response = misc:httpc_request(head, {URL, []}, [], []),
            process_response(Message, Response, URL)
    end.

process_response(Message, {{_, 200, _}, List, _}, URL) ->
    {"content-type", Type} = lists:keyfind("content-type", 1, List),
    lager:debug("[~s] type: ~p", [?MODULE, Type]),
    Position = string:str(Type, "text/html"),
    if Position >= 1 ->
            Response = misc:httpc_request(get, {URL, []}, [], []),
            process_response2(Message, Response);
        true ->
            ImageFormats = ["image/png", "image/gif", "image/jpeg", "image/webp"],
            Exist = lists:member(Type, ImageFormats),
            RoomJid = message:from_room(Message),
            case Type of
                _ when Exist == true ->
                    {"content-length", LengthStr} = lists:keyfind("content-length", 1, List),
                    {Length, _} = string:to_integer(LengthStr),
                    HumanLen = float_to_list(Length/1024,[{decimals, 2}, compact]),
                    jid_worker:reply("Content-type: " ++ Type ++ ", length: " ++ HumanLen ++ " KiB", RoomJid);
                _ ->
                    jid_worker:reply("Content-type: " ++ Type, RoomJid)
            end
    end;
process_response(_Message, _Other, _URL) ->
    ok.

process_response2(Message, {{_, 200, _}, _, Page}) ->
    MaybeTitle = extract_title(mochiweb_html:parse(Page)),
            case MaybeTitle of
                false ->
                    ok;
                {<<"title">>, [], [Title]} ->
                    From = exmpp_xml:get_attribute(message:raw(Message), <<"from">>, undefined),
                    [RoomJid|_] = string:tokens(misc:format_str("~s",[From]),"/"),
                    jid_worker:reply("Page title: " ++ Title, RoomJid);
                Any ->
                    lager:error("[~s] got title tag: ~s", [?MODULE, Any]),
                    ok
            end;
process_response2(_Message, _Other) ->
    ok.

extract_title({<<"html">>, C, [{comment, _}|T]}) ->
    extract_title({<<"html">>, C, T});
extract_title({<<"html">>, _, [{<<"head">>, _, HeadChildren}|_]}) ->
    lists:keyfind(<<"title">>, 1, HeadChildren);
extract_title({<<"head">>, _, HeadChildren}) ->
    lists:keyfind(<<"title">>, 1, HeadChildren);
extract_title(SomethingElse) ->
    lager:info("Mysterios occurence. Investigation required!"),
    lager:info("mochiveb parsed: ~t", [SomethingElse]).
