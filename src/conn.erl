%% ===================================================================
%% 实现玩家进程逻辑
%% ===================================================================
-module(conn).
-behavior(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([start_link/1,
         send/2,
         stop/1]).

%% 连接进程状态
-record(state, {
          recv_cnt = 0,                  %% 读取到的数据个数
          socket,                        %% 与进程关联的 socket
          player_id                      %% 玩家ID
         }).

-include("proto.hrl").

start_link(Socket) ->
  gen_server:start_link(?MODULE, [Socket], []).

stop(Ref) ->
  gen_server:cast(Ref, stop).

init([Socket]) ->
  process_flag(trap_exit, true),
  inet:setopts(Socket, [{active, once}, {packet, 2}, binary]),
  State = #state{socket = Socket},
  erlang:put(socket, Socket),
  {ok, State}.

handle_cast(Cast, State) ->
  State1 = conn_config:exec(cast, [Cast, State]),
  {noreply, State1}.

handle_call(Call, From, State) ->
  State1 = conn_config:exec(cast, [Call, From, State]),
  {reply, ok, State1}.

handle_info({tcp_closed, Socket}, State)
  when Socket == State#state.socket ->
  {stop, normal, State};

handle_info({tcp_error, _Port, _Reason}, State) ->
  {noreply, State};

handle_info({tcp, Socket, Bin}, State) ->
  inet:setopts(Socket, [{active, once}, {packet, 2}, binary]),
  <<Type:?HWORD, RequestData/binary>> = Bin,
  ?M(Payload) = proto_decoder:decode(Type, RequestData),
  {M, F} = proto_route:route(Type),
  M:F(Payload),
  keep_alive_or_close(keep_alive, State);

handle_info(Info, State) ->
  conn_config:exec(info, [Info, State]),
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
terminate(Reason, State) ->
  conn_config:exec(quit, [Reason, State]),
  ok.

keep_alive_or_close(Keep, State) ->
  if
    Keep /= keep_alive -> gen_tcp:close(State#state.socket),
                          {stop, normal, State};
    true -> {noreply, State}
  end.

%% 一些副作用代码
send(TypeAtom, Paylod) ->
  Socket = erlang:get(socket),
  Type = proto_api:key(TypeAtom),
  Bin = proto_encoder:encode(Type, Paylod),
  gen_tcp:send(Socket, Bin),
  ok.
