%% JSON-RPC for Cowboy
%%---------------------------------------------------------------------------
%% @author Erik Timan <dev@timan.info>
%% @author Tony Garnock-Jones <tonygarnockjones@gmail.com>
%% @author LShift Ltd. <query@lshift.net>
%% @copyright 2007-2010, 2011, 2012 Tony Garnock-Jones and 2007-2010 LShift Ltd.
%% @license
%%
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use, copy,
%% modify, merge, publish, distribute, sublicense, and/or sell copies
%% of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
%% BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
%% ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
%% CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.
%%---------------------------------------------------------------------------
%%
%% @reference the <a href="http://github.com/extend/cowboy/">Cowboy github page</a>
%%
%% @doc Support for serving JSON-RPC via Cowboy.
%%
%% Familiarity with writing Cowboy applications is assumed.
%%
%% == Basic Usage ==
%%
%% <ul>
%% <li>Register your JSON-RPC services as usual.</li>
%% <li>Decide on your `AliasPrefix' (see {@link rfc4627_jsonrpc_http:invoke_service_method/4}).</li>
%% <li>When a Cowboy request arrives at your application, call {@link handle/2} with your `AliasPrefix' and the request.</li>
%% </ul>
%%
%% It's as simple as that - if the request's URI path matches the
%% `AliasPrefix', it will be decoded and the JSON-RPC service it names
%% will be invoked.

-module(rfc4627_jsonrpc_cowboy).

-export([handle/2]).

normalize(X) when is_atom(X) ->
    string:to_lower(atom_to_list(X));
normalize(X) when is_binary(X) ->
    string:to_lower(binary_to_list(X));
normalize(X) when is_list(X) ->
    string:to_lower(X).

%% @spec (string(), #http_req{}) -> no_match | {ok, #http_req{}}
%%
%% @doc If the request matches `AliasPrefix', the corresponding
%% JSON-RPC service is invoked, and an `{ok, #http_req{}}' is returned;
%% otherwise, `no_match' is returned.
%%
%% Call this function from your Cowboy HTTP handler's `handle'
%% function, as follows:
%%
%% ```
%% Req2 = case rfc4627_jsonrpc_cowboy:handle("/rpc", Req) of
%%           no_match ->
%%               handle_non_jsonrpc_request(Req);
%%           {ok, Reponse} ->
%%               Response
%%       end
%% '''
%%
%% where `handle_non_jsonrpc_request' does the obvious thing for
%% non-JSON-RPC requests.
handle(AliasPrefix, Req) ->
    {BinaryPath, _} = cowboy_req:path(Req),
    Path = binary_to_list(BinaryPath),
    {QSVals, _} = cowboy_req:qs_vals(Req),
    QueryObj = {obj, [{binary_to_list(K), V} || {K,V} <- QSVals]},
    {Hdrs, _} = cowboy_req:headers(Req),
    HeaderObj = {obj, [{normalize(K), V} || {K,V} <- Hdrs]},
    {PeerAddr, _} = cowboy_req:peer_addr(Req),
    Peer = list_to_binary(inet_parse:ntoa(PeerAddr)),
    {Method, _} = cowboy_req:method(Req),
    RequestInfo = {obj, [{"http_method", Method},
                         {"http_query_parameters", QueryObj},
                         {"http_headers", HeaderObj},
                         {"remote_peername", Peer},
                         {"scheme", <<"http">>}]},
    {ok, Body, _} = cowboy_req:body(Req),

    case rfc4627_jsonrpc_http:invoke_service_method(AliasPrefix,
                                                    Path,
                                                    RequestInfo,
                                                    Body) of
        no_match ->
            no_match;
        {ok, ResultEnc, ResponseInfo} ->
            {obj, ResponseHeaderFields} =
                rfc4627:get_field(ResponseInfo, "http_headers", {obj, []}),
            StatusCode =
                rfc4627:get_field(ResponseInfo, "http_status_code", 200),
            Headers = [{list_to_binary(K), V} || {K,V} <- ResponseHeaderFields],
            RespType = [{<<"Content-Type">>, rfc4627:mime_type()}],
            cowboy_req:reply(StatusCode,
                              Headers ++ RespType,
                              ResultEnc,
                              Req)
    end.
