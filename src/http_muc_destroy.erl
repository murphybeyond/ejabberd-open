-module(http_muc_destroy).

-export([handle/1]).
-include("ejabberd.hrl").
-include("logger.hrl").

-record(muc_online_room, {name_host = {<<"">>, <<"">>} :: {binary(), binary()} | '$1' | {'_', binary()} | '_',
		                            pid = self() :: pid() | '$2' | '_' | '$1'}).

handle(Req) ->
    {Method, _} = cowboy_req:method(Req),
    case Method of 
        <<"POST">> ->
            do_handle(Req);
        _ ->
            http_utils:cowboy_req_reply_json(http_utils:gen_fail_result(1, <<Method/binary, " is not disable">>), Req)
    end.

do_handle(Req)->
    {ok, Body, Req1} = cowboy_req:body(Req),
    case rfc4627:decode(Body) of
    {ok,{obj,Args},[]}  ->
        Res = destroy_muc(Args),
        http_utils:cowboy_req_reply_json(Res, Req1);
    _ ->
        http_utils:cowboy_req_reply_json(http_utils:gen_fail_result(1,<<"Json format error.">>), Req1)
    end.

destroy_muc(Args) ->
    Servers = ejabberd_config:get_myhosts(),
    LServer = lists:nth(1,Servers),
    destroy_muc(LServer,Args).

destroy_muc(LServer,Args) ->
    Room = http_muc_session:get_value("muc_id",Args,<<"">>),
    Server_Host = http_muc_session:get_value("muc_domain",Args,<<"">>),
    Muc_Owner =	http_muc_session:get_value("muc_owner",Args,<<"">>),
    Host = http_muc_session:get_value("host",Args,LServer),
    Owner = jlib:jid_to_string({Muc_Owner,Host,<<"">>}),
    case mod_muc:check_muc_owner(Host,Room,Owner) of
    true ->
        case mod_muc_redis:get_muc_room_pid(Room, Server_Host) of
        [] ->
            mod_muc:forget_room(LServer,Server_Host ,Room),
            catch qtalk_sql:restore_muc_user_mark(LServer,Room),
            catch qtalk_sql:del_muc_users(LServer,Room,Server_Host),
            catch qtalk_sql:del_user_register_mucs(LServer,Room,Server_Host),
            catch qtalk_sql:del_muc_vcard_info(LServer,Room,<<"Admin Destroy">>);
        [M] ->
            ?INFO_MSG("Destory Room ~s  by management cmd ~n",[Room]),
            Pid = M#muc_online_room.pid,
            gen_fsm:send_all_state_event(Pid, {destroy, <<"management close">>}),
            mod_muc:room_destroyed(Server_Host, Room,Pid, LServer),
            mod_muc:forget_room(LServer,Server_Host ,Room),
            Pid ! shutdown,
            catch qtalk_sql:restore_muc_user_mark(LServer,Room),
            catch qtalk_sql:del_muc_users(LServer,Room,Server_Host),
            catch qtalk_sql:del_user_register_mucs(LServer,Room,Server_Host),
            catch qtalk_sql:del_muc_vcard_info(LServer,Room,<<"Admin Destroy">>)
        end,
        http_utils:gen_result(true, <<"0">>,<<"">>,<<"sucess">>);
    _ ->
        http_utils:gen_result(true, <<"1">>,<<"">>,<<"failed">>)
    end.
