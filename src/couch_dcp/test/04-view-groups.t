#!/usr/bin/env escript
%% -*- Mode: Erlang; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
%%! -smp enable

% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-include("../../couchdb/couch_db.hrl").
-include_lib("couch_set_view/include/couch_set_view.hrl").


test_set_name() -> <<"couch_test_dcp_view_groups">>.
num_set_partitions() -> 4.
ddoc_id() -> <<"_design/test">>.
num_docs() -> 1024.  % keep it a multiple of num_set_partitions()
num_docs_pp() -> 1024 div num_set_partitions().


main(_) ->
    test_util:init_code_path(),

    etap:plan(16),
    case (catch test()) of
        ok ->
            etap:end_tests();
        Other ->
            etap:diag(io_lib:format("Test died abnormally: ~p", [Other])),
            etap:bail(Other)
    end,
    ok.


test() ->
    couch_set_view_test_util:start_server(test_set_name()),
    etap:diag("Testing DCP in regards to view groups"),

    test_partition_versions_update(),
    test_rollback_different_heads(),
    test_persisted_items(),
    test_mutliple_snapshots(),
    test_duplicates(),

    couch_set_view_test_util:stop_server(),
    ok.

test_partition_versions_update() ->
    etap:diag("Testing whether the view partition versions are updated or not"),

    setup_test(),
    {auth, User, Passwd} = cb_auth_info:get(),
    {ok, Pid} = couch_dcp_client:start(
            test_set_name(), test_set_name(), User, Passwd, 20*1024*1024, 0),

    {ok, InitialFailoverLog1} = couch_dcp_client:get_failover_log(Pid, 1),
    {ok, InitialFailoverLog2} = couch_dcp_client:get_failover_log(Pid, 2),
    {ok, {_ViewResults1}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, []),

    GroupFailoverLog1 = get_group_failover_log(1),
    GroupFailoverLog2 = get_group_failover_log(2),
    etap:is(GroupFailoverLog1, InitialFailoverLog1,
        "Group failover log of partition 1 is the same as "
        "initial failover log"),
    etap:is(GroupFailoverLog2, InitialFailoverLog2,
        "Group failover log of partition 2 is the same as "
        "initial failover log"),

    FailoverLog2 = InitialFailoverLog2 ++ [{222331, 10}],
    couch_dcp_fake_server:set_failover_log(2, FailoverLog2),
    % Insert new docs so that the updater is run on the new query
    populate_set(num_docs() + 1, 2 * num_docs()),
    {ok, {_ViewResults2}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, []),

    GroupFailoverLog1b = get_group_failover_log(1),
    GroupFailoverLog2b = get_group_failover_log(2),
    etap:is(GroupFailoverLog1b, InitialFailoverLog1,
        "Group failover log of partition 1 is still the same as "
        "initial failover log"),
    etap:is(GroupFailoverLog2b, FailoverLog2,
        "Group failover log of partition 2 got correctly updated"),

    shutdown_group().


test_rollback_different_heads() ->
    % The testcase is: server and client have a shared history. The most
    % recent failover log entry differs. The most recent entry from the server
    % has a lower high squence number than the client has. The client needs
    % to retry with an older version of its failover log. Then a rollback
    % should happen. And finally the indexing should catch up again.
    etap:diag("Testing a rollback where the server and the client have "
        "a common history except for the most recent one, where both differ"),

    % Give the DCP server a failover log we can diverge from
    FailoverLog = [
        {10001, (num_docs_pp() * 2)},
        {10002, num_docs_pp()},
        {10003, 0}],

    {ViewResultNoRollback, FailoverLogNoRollback} = rollback_different_heads(
        dont_force_a_rollback, FailoverLog),
    {ViewResultRollback, FailoverLogRollback} = rollback_different_heads(
        force_a_rollback, FailoverLog),
    etap:is(ViewResultRollback, ViewResultNoRollback,
        "View results are the same with and without a rollback"),
    etap:isnt(FailoverLogRollback, FailoverLogNoRollback,
        "The failover log is different between the two runs"),
    ok.

rollback_different_heads(DoRollback, FailoverLog) ->
    Msg = case DoRollback of
    dont_force_a_rollback ->
        "Query data without rollback";
    force_a_rollback ->
        "Query data with rollback"
    end,
    etap:diag(Msg),

    setup_test(),
    PartId = 1,
    couch_dcp_fake_server:set_failover_log(PartId, FailoverLog),

    % Update index twice, so that there are header to roll back to
    {ok, {_ViewResults1}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, []),
    populate_set(num_docs() + 1, 2 * num_docs()),
    {ok, {_ViewResults2}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, []),
    GroupFailoverLog = get_group_failover_log(PartId),
    etap:is(GroupFailoverLog, FailoverLog,
        "Group has initially the correct failover log"),

    case DoRollback of
    dont_force_a_rollback ->
        FailoverLog2 = FailoverLog;
    force_a_rollback ->
        % Change the failover log on the server that is different from what
        % The client has, so that a rollback is needed
        FailoverLog2 = [{777888999, num_docs_pp() + 10}] ++
            tl(FailoverLog),
        couch_dcp_fake_server:set_failover_log(PartId, FailoverLog2)
    end,

    % Insert new docs so that the updater is run on the new query
    populate_set((num_docs() * 2) + 1, 3 * num_docs()),
    {ok, {ViewResults3}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, []),
    GroupFailoverLog2 = get_group_failover_log(PartId),
    etap:is(GroupFailoverLog2, FailoverLog2,
        "Group has correct failover log after it might have changed"),

    shutdown_group(),
    {ViewResults3, FailoverLog2}.


test_persisted_items() ->
    etap:diag("Test the initial index build with a persisted sequence number "
        "which is lower than the current high sequence"),

    % First query with persisted sequence number == high sequence number
    setup_test(),
    couch_dcp_fake_server:set_persisted_items_fun(fun(Seq) -> Seq end),
    {ok, {ViewResults1}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    shutdown_group(),

    % Then with persisted sequence number == high sequence number / 2
    setup_test(),
    couch_dcp_fake_server:set_persisted_items_fun(
        fun(Seq) -> max(Seq div 2, 1) end),
    {ok, {ViewResults2}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    etap:is(ViewResults1, ViewResults2,
        "Having a persisted sequence number lower than the high sequence "
        "number doesn't make difference (a)"),
    shutdown_group(),

    % Then with persisted sequence number == high sequence number - 1
    setup_test(),
    couch_dcp_fake_server:set_persisted_items_fun(
        fun(Seq) -> max(Seq - 1, 1) end),
    {ok, {ViewResults3}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    etap:is(ViewResults1, ViewResults3,
        "Having a persisted sequence number lower than the high sequence "
        "number doesn't make difference (b)"),
    shutdown_group(),
    ok.


test_mutliple_snapshots() ->
    etap:diag("Test the index build with receiving several snapshots"),

    % First query with the result returning in a single snapshot
    setup_test(),
    couch_dcp_fake_server:set_items_per_snapshot(0),
    {ok, {ViewResults1}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    shutdown_group(),

    % Then with the result returning in several snapshots
    setup_test(),
    couch_dcp_fake_server:set_items_per_snapshot(num_docs_pp() div 4),
    {ok, {ViewResults2}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    etap:is(ViewResults1, ViewResults2,
        "The results of the single snapshot is the same as with multiple "
        "snapshots (a)"),
    shutdown_group(),

    % Try again with some other number of snapshots
    setup_test(),
    couch_dcp_fake_server:set_items_per_snapshot(num_docs_pp() div 3),
    {ok, {ViewResults3}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    etap:is(ViewResults1, ViewResults3,
        "The results of the single snapshot is the same as with multiple "
        "snapshots (b)"),
    shutdown_group(),
    ok.


test_duplicates() ->
    etap:diag("Test the index build with receiving duplicates within several "
      "snapshots"),

    % First query with the result returning in a single snapshot
    setup_test(),
    couch_dcp_fake_server:set_items_per_snapshot(0),
    {ok, {ViewResults1}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    shutdown_group(),

    % Then with the result where the stream contains duplicates
    setup_test(),
    couch_dcp_fake_server:set_items_per_snapshot(num_docs_pp() div 4),
    couch_dcp_fake_server:set_dups_per_snapshot(num_docs_pp() div 9),
    {ok, {ViewResults2}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    etap:is(ViewResults2, ViewResults1,
        "The results of the single snapshot is the same as with multiple "
        "snapshots containing duplicates (a)"),
    shutdown_group(),

    % Try again with some other number of duplicates
    setup_test(),
    couch_dcp_fake_server:set_items_per_snapshot(num_docs_pp() div 3),
    couch_dcp_fake_server:set_dups_per_snapshot(num_docs_pp() div 10),
    {ok, {ViewResults3}} = couch_set_view_test_util:query_view(
        test_set_name(), ddoc_id(), <<"test">>, ["stale=false"]),
    etap:is(ViewResults3, ViewResults1,
        "The results of the single snapshot is the same as with multiple "
        "snapshots containing duplicates (b)"),
    shutdown_group(),
    ok.


setup_test() ->
    couch_set_view_test_util:delete_set_dbs(test_set_name(), num_set_partitions()),
    couch_set_view_test_util:create_set_dbs(test_set_name(), num_set_partitions()),
    populate_set(1, num_docs()),

    DDoc = {[
        {<<"meta">>, {[{<<"id">>, ddoc_id()}]}},
        {<<"json">>, {[
            {<<"views">>, {[
                {<<"test">>, {[
                    {<<"map">>, <<"function(doc, meta) { emit(meta.id, doc.value); }">>}
                ]}}
            ]}}
        ]}}
    ]},
    ok = couch_set_view_test_util:update_ddoc(test_set_name(), DDoc),
    ok = configure_view_group().

shutdown_group() ->
    couch_dcp_fake_server:reset(),
    GroupPid = couch_set_view:get_group_pid(
        mapreduce_view, test_set_name(), ddoc_id(), prod),
    couch_set_view_test_util:delete_set_dbs(test_set_name(), num_set_partitions()),
    MonRef = erlang:monitor(process, GroupPid),
    receive
    {'DOWN', MonRef, _, _, _} ->
        ok
    after 10000 ->
        etap:bail("Timeout waiting for group shutdown")
    end.


populate_set(From, To) ->
    etap:diag("Populating the " ++ integer_to_list(num_set_partitions()) ++
        " databases with " ++ integer_to_list(num_docs()) ++ " documents"),
    DocList = create_docs(From, To),
    ok = couch_set_view_test_util:populate_set_sequentially(
        test_set_name(),
        lists:seq(0, num_set_partitions() - 1),
        DocList).

doc_id(I) ->
    iolist_to_binary(io_lib:format("doc_~8..0b", [I])).

create_docs(From, To) ->
    lists:map(
        fun(I) ->
            Cas = I,
            ExpireTime = 0,
            Flags = 0,
            RevMeta1 = <<Cas:64/native, ExpireTime:32/native, Flags:32/native>>,
            RevMeta2 = [[io_lib:format("~2.16.0b",[X]) || <<X:8>> <= RevMeta1 ]],
            RevMeta3 = iolist_to_binary(RevMeta2),
            {[
              {<<"meta">>, {[
                             {<<"id">>, doc_id(I)},
                             {<<"rev">>, <<"1-", RevMeta3/binary>>}
                            ]}},
              {<<"json">>, {[{<<"value">>, I}]}}
            ]}
        end,
        lists:seq(From, To)).


configure_view_group() ->
    etap:diag("Configuring view group"),
    Params = #set_view_params{
        max_partitions = num_set_partitions(),
        active_partitions = lists:seq(0, num_set_partitions()-1),
        passive_partitions = [],
        use_replica_index = false
    },
    try
        couch_set_view:define_group(
            mapreduce_view, test_set_name(), ddoc_id(), Params)
    catch _:Error ->
        Error
    end.


get_group_info() ->
    GroupPid = couch_set_view:get_group_pid(
        mapreduce_view, test_set_name(), ddoc_id(), prod),
    {ok, GroupInfo} = couch_set_view_group:request_group_info(GroupPid),
    GroupInfo.

get_group_failover_log(PartId) ->
    GroupInfo = get_group_info(),
    {partition_versions, {PartVersions0}} = lists:keyfind(
        partition_versions, 1, GroupInfo),
    PartVersions = lists:map(fun({PartId0, PartVersion}) ->
        {list_to_integer(binary_to_list(PartId0)),
            [list_to_tuple(V) || V <- PartVersion]}
    end, PartVersions0),
    {PartId, FailoverLog} = lists:keyfind(PartId, 1, PartVersions),
    FailoverLog.
