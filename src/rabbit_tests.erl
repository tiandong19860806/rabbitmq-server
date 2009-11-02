%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ.
%%
%%   The Initial Developers of the Original Code are LShift Ltd,
%%   Cohesive Financial Technologies LLC, and Rabbit Technologies Ltd.
%%
%%   Portions created before 22-Nov-2008 00:00:00 GMT by LShift Ltd,
%%   Cohesive Financial Technologies LLC, or Rabbit Technologies Ltd
%%   are Copyright (C) 2007-2008 LShift Ltd, Cohesive Financial
%%   Technologies LLC, and Rabbit Technologies Ltd.
%%
%%   Portions created by LShift Ltd are Copyright (C) 2007-2009 LShift
%%   Ltd. Portions created by Cohesive Financial Technologies LLC are
%%   Copyright (C) 2007-2009 Cohesive Financial Technologies
%%   LLC. Portions created by Rabbit Technologies Ltd are Copyright
%%   (C) 2007-2009 Rabbit Technologies Ltd.
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): ______________________________________.
%%

-module(rabbit_tests).

-compile(export_all).

-export([all_tests/0, test_parsing/0]).

%% Exported so the hook mechanism can call back
-export([handle_hook/3, bad_handle_hook/3, extra_arg_hook/5]).

-import(lists).

-include("rabbit.hrl").
-include_lib("kernel/include/file.hrl").

test_content_prop_roundtrip(Datum, Binary) ->
    Types =  [element(1, E) || E <- Datum],
    Values = [element(2, E) || E <- Datum],
    Values = rabbit_binary_parser:parse_properties(Types, Binary), %% assertion
    Binary = rabbit_binary_generator:encode_properties(Types, Values). %% assertion

all_tests() ->
    passed = test_msg_store(),
    passed = test_queue_index(),
    passed = test_priority_queue(),
    passed = test_unfold(),
    passed = test_parsing(),
    passed = test_topic_matching(),
    passed = test_log_management(),
    passed = test_app_management(),
    passed = test_log_management_during_startup(),
    passed = test_cluster_management(),
    passed = test_user_management(),
    passed = test_server_status(),
    passed = test_hooks(),
    passed.

test_priority_queue() ->

    false = priority_queue:is_queue(not_a_queue),

    %% empty Q
    Q = priority_queue:new(),
    {true, true, 0, [], []} = test_priority_queue(Q),

    %% 1-4 element no-priority Q
    true = lists:all(fun (X) -> X =:= passed end,
                     lists:map(fun test_simple_n_element_queue/1,
                               lists:seq(1, 4))),

    %% 1-element priority Q
    Q1 = priority_queue:in(foo, 1, priority_queue:new()),
    {true, false, 1, [{1, foo}], [foo]} =
        test_priority_queue(Q1),

    %% 2-element same-priority Q
    Q2 = priority_queue:in(bar, 1, Q1),
    {true, false, 2, [{1, foo}, {1, bar}], [foo, bar]} =
        test_priority_queue(Q2),

    %% 2-element different-priority Q
    Q3 = priority_queue:in(bar, 2, Q1),
    {true, false, 2, [{2, bar}, {1, foo}], [bar, foo]} =
        test_priority_queue(Q3),

    %% 1-element negative priority Q
    Q4 = priority_queue:in(foo, -1, priority_queue:new()),
    {true, false, 1, [{-1, foo}], [foo]} = test_priority_queue(Q4),

    %% merge 2 * 1-element no-priority Qs
    Q5 = priority_queue:join(priority_queue:in(foo, Q),
                             priority_queue:in(bar, Q)),
    {true, false, 2, [{0, foo}, {0, bar}], [foo, bar]} =
        test_priority_queue(Q5),

    %% merge 1-element no-priority Q with 1-element priority Q
    Q6 = priority_queue:join(priority_queue:in(foo, Q),
                             priority_queue:in(bar, 1, Q)),
    {true, false, 2, [{1, bar}, {0, foo}], [bar, foo]} =
        test_priority_queue(Q6),

    %% merge 1-element priority Q with 1-element no-priority Q 
    Q7 = priority_queue:join(priority_queue:in(foo, 1, Q),
                             priority_queue:in(bar, Q)),
    {true, false, 2, [{1, foo}, {0, bar}], [foo, bar]} =
        test_priority_queue(Q7),

    %% merge 2 * 1-element same-priority Qs
    Q8 = priority_queue:join(priority_queue:in(foo, 1, Q),
                             priority_queue:in(bar, 1, Q)),
    {true, false, 2, [{1, foo}, {1, bar}], [foo, bar]} =
        test_priority_queue(Q8),

    %% merge 2 * 1-element different-priority Qs
    Q9 = priority_queue:join(priority_queue:in(foo, 1, Q),
                             priority_queue:in(bar, 2, Q)),
    {true, false, 2, [{2, bar}, {1, foo}], [bar, foo]} =
        test_priority_queue(Q9),

    %% merge 2 * 1-element different-priority Qs (other way around)
    Q10 = priority_queue:join(priority_queue:in(bar, 2, Q),
                              priority_queue:in(foo, 1, Q)),
    {true, false, 2, [{2, bar}, {1, foo}], [bar, foo]} =
        test_priority_queue(Q10),

    %% merge 2 * 2-element multi-different-priority Qs
    Q11 = priority_queue:join(Q6, Q5),
    {true, false, 4, [{1, bar}, {0, foo}, {0, foo}, {0, bar}],
     [bar, foo, foo, bar]} = test_priority_queue(Q11),

    %% and the other way around
    Q12 = priority_queue:join(Q5, Q6),
    {true, false, 4, [{1, bar}, {0, foo}, {0, bar}, {0, foo}],
     [bar, foo, bar, foo]} = test_priority_queue(Q12),

    %% merge with negative priorities
    Q13 = priority_queue:join(Q4, Q5),
    {true, false, 3, [{0, foo}, {0, bar}, {-1, foo}], [foo, bar, foo]} =
        test_priority_queue(Q13),

    %% and the other way around
    Q14 = priority_queue:join(Q5, Q4),
    {true, false, 3, [{0, foo}, {0, bar}, {-1, foo}], [foo, bar, foo]} =
        test_priority_queue(Q14),

    %% joins with empty queues:
    Q1 = priority_queue:join(Q, Q1),
    Q1 = priority_queue:join(Q1, Q),

    %% insert with priority into non-empty zero-priority queue
    Q15 = priority_queue:in(baz, 1, Q5),
    {true, false, 3, [{1, baz}, {0, foo}, {0, bar}], [baz, foo, bar]} =
        test_priority_queue(Q15),

    passed.

priority_queue_in_all(Q, L) ->
    lists:foldl(fun (X, Acc) -> priority_queue:in(X, Acc) end, Q, L).

priority_queue_out_all(Q) ->
    case priority_queue:out(Q) of
        {empty, _}       -> [];
        {{value, V}, Q1} -> [V | priority_queue_out_all(Q1)]
    end.
test_priority_queue(Q) ->
    {priority_queue:is_queue(Q),
     priority_queue:is_empty(Q),
     priority_queue:len(Q),
     priority_queue:to_list(Q),
     priority_queue_out_all(Q)}.

test_simple_n_element_queue(N) ->
    Items = lists:seq(1, N),
    Q = priority_queue_in_all(priority_queue:new(), Items),
    ToListRes = [{0, X} || X <- Items],
    {true, false, N, ToListRes, Items} = test_priority_queue(Q),
    passed.

test_unfold() ->
    {[], test} = rabbit_misc:unfold(fun (_V) -> false end, test),
    List = lists:seq(2,20,2),
    {List, 0} = rabbit_misc:unfold(fun (0) -> false;
                                       (N) -> {true, N*2, N-1}
                                   end, 10),
    passed.

test_parsing() ->
    passed = test_content_properties(),
    passed.

test_content_properties() ->
    test_content_prop_roundtrip([], <<0, 0>>),
    test_content_prop_roundtrip([{bit, true}, {bit, false}, {bit, true}, {bit, false}],
                                <<16#A0, 0>>),
    test_content_prop_roundtrip([{bit, true}, {octet, 123}, {bit, true}, {octet, undefined},
                                 {bit, true}],
                                <<16#E8,0,123>>),
    test_content_prop_roundtrip([{bit, true}, {octet, 123}, {octet, 123}, {bit, true}],
                                <<16#F0,0,123,123>>),
    test_content_prop_roundtrip([{bit, true}, {shortstr, <<"hi">>}, {bit, true},
                                 {shortint, 54321}, {bit, true}],
                                <<16#F8,0,2,"hi",16#D4,16#31>>),
    test_content_prop_roundtrip([{bit, true}, {shortstr, undefined}, {bit, true},
                                 {shortint, 54321}, {bit, true}],
                                <<16#B8,0,16#D4,16#31>>),
    test_content_prop_roundtrip([{table, [{<<"a signedint">>, signedint, 12345678},
                                          {<<"a longstr">>, longstr, <<"yes please">>},
                                          {<<"a decimal">>, decimal, {123, 12345678}},
                                          {<<"a timestamp">>, timestamp, 123456789012345},
                                          {<<"a nested table">>, table,
                                           [{<<"one">>, signedint, 1},
                                            {<<"two">>, signedint, 2}]}]}],
                                <<
                                 16#8000:16,                % flags
                                 % properties:

                                 117:32,                % table length in bytes

                                 11,"a signedint",        % name
                                 "I",12345678:32,        % type and value

                                 9,"a longstr",
                                 "S",10:32,"yes please",

                                 9,"a decimal",
                                 "D",123,12345678:32,

                                 11,"a timestamp",
                                 "T", 123456789012345:64,

                                 14,"a nested table",
                                 "F",
                                        18:32,

                                        3,"one",
                                        "I",1:32,

                                        3,"two",
                                        "I",2:32 >>),
    case catch rabbit_binary_parser:parse_properties([bit, bit, bit, bit], <<16#A0,0,1>>) of
        {'EXIT', content_properties_binary_overflow} -> passed;
        V -> exit({got_success_but_expected_failure, V})
    end.

test_topic_match(P, R) ->
    test_topic_match(P, R, true).

test_topic_match(P, R, Expected) ->
    case rabbit_exchange:topic_matches(list_to_binary(P), list_to_binary(R)) of
        Expected ->
            passed;
        _ ->
            {topic_match_failure, P, R}
    end.

test_topic_matching() ->
    passed = test_topic_match("#", "test.test"),
    passed = test_topic_match("#", ""),
    passed = test_topic_match("#.T.R", "T.T.R"),
    passed = test_topic_match("#.T.R", "T.R.T.R"),
    passed = test_topic_match("#.Y.Z", "X.Y.Z.X.Y.Z"),
    passed = test_topic_match("#.test", "test"),
    passed = test_topic_match("#.test", "test.test"),
    passed = test_topic_match("#.test", "ignored.test"),
    passed = test_topic_match("#.test", "more.ignored.test"),
    passed = test_topic_match("#.test", "notmatched", false),
    passed = test_topic_match("#.z", "one.two.three.four", false),
    passed.

test_app_management() ->
    %% starting, stopping, status
    ok = control_action(stop_app, []),
    ok = control_action(stop_app, []),
    ok = control_action(status, []),
    ok = control_action(start_app, []),
    ok = control_action(start_app, []),
    ok = control_action(status, []),
    passed.

test_log_management() ->
    MainLog = rabbit:log_location(kernel),
    SaslLog = rabbit:log_location(sasl),
    Suffix = ".1",

    %% prepare basic logs
    file:delete([MainLog, Suffix]),
    file:delete([SaslLog, Suffix]),

    %% simple logs reopening
    ok = control_action(rotate_logs, []),
    [true, true] = empty_files([MainLog, SaslLog]),
    ok = test_logs_working(MainLog, SaslLog),

    %% simple log rotation
    ok = control_action(rotate_logs, [Suffix]),
    [true, true] = non_empty_files([[MainLog, Suffix], [SaslLog, Suffix]]),
    [true, true] = empty_files([MainLog, SaslLog]),
    ok = test_logs_working(MainLog, SaslLog),

    %% reopening logs with log rotation performed first
    ok = clean_logs([MainLog, SaslLog], Suffix),
    ok = control_action(rotate_logs, []),
    ok = file:rename(MainLog, [MainLog, Suffix]),
    ok = file:rename(SaslLog, [SaslLog, Suffix]),
    ok = test_logs_working([MainLog, Suffix], [SaslLog, Suffix]),
    ok = control_action(rotate_logs, []),
    ok = test_logs_working(MainLog, SaslLog),

    %% log rotation on empty file
    ok = clean_logs([MainLog, SaslLog], Suffix),
    ok = control_action(rotate_logs, []),
    ok = control_action(rotate_logs, [Suffix]),
    [true, true] = empty_files([[MainLog, Suffix], [SaslLog, Suffix]]),

    %% original main log file is not writable
    ok = make_files_non_writable([MainLog]),
    {error, {cannot_rotate_main_logs, _}} = control_action(rotate_logs, []),
    ok = clean_logs([MainLog], Suffix),
    ok = add_log_handlers([{rabbit_error_logger_file_h, MainLog}]),

    %% original sasl log file is not writable
    ok = make_files_non_writable([SaslLog]),
    {error, {cannot_rotate_sasl_logs, _}} = control_action(rotate_logs, []),
    ok = clean_logs([SaslLog], Suffix),
    ok = add_log_handlers([{rabbit_sasl_report_file_h, SaslLog}]),

    %% logs with suffix are not writable
    ok = control_action(rotate_logs, [Suffix]),
    ok = make_files_non_writable([[MainLog, Suffix], [SaslLog, Suffix]]),
    ok = control_action(rotate_logs, [Suffix]),
    ok = test_logs_working(MainLog, SaslLog),

    %% original log files are not writable
    ok = make_files_non_writable([MainLog, SaslLog]),
    {error, {{cannot_rotate_main_logs, _},
             {cannot_rotate_sasl_logs, _}}} = control_action(rotate_logs, []),

    %% logging directed to tty (handlers were removed in last test)
    ok = clean_logs([MainLog, SaslLog], Suffix),
    ok = application:set_env(sasl, sasl_error_logger, tty),
    ok = application:set_env(kernel, error_logger, tty),
    ok = control_action(rotate_logs, []),
    [{error, enoent}, {error, enoent}] = empty_files([MainLog, SaslLog]),

    %% rotate logs when logging is turned off
    ok = application:set_env(sasl, sasl_error_logger, false),
    ok = application:set_env(kernel, error_logger, silent),
    ok = control_action(rotate_logs, []),
    [{error, enoent}, {error, enoent}] = empty_files([MainLog, SaslLog]),

    %% cleanup
    ok = application:set_env(sasl, sasl_error_logger, {file, SaslLog}),
    ok = application:set_env(kernel, error_logger, {file, MainLog}),
    ok = add_log_handlers([{rabbit_error_logger_file_h, MainLog},
                           {rabbit_sasl_report_file_h, SaslLog}]),
    passed.

test_log_management_during_startup() ->
    MainLog = rabbit:log_location(kernel),
    SaslLog = rabbit:log_location(sasl),

    %% start application with simple tty logging
    ok = control_action(stop_app, []),
    ok = application:set_env(kernel, error_logger, tty),
    ok = application:set_env(sasl, sasl_error_logger, tty),
    ok = add_log_handlers([{error_logger_tty_h, []},
                           {sasl_report_tty_h, []}]),
    ok = control_action(start_app, []),

    %% start application with tty logging and 
    %% proper handlers not installed
    ok = control_action(stop_app, []),
    ok = error_logger:tty(false),
    ok = delete_log_handlers([sasl_report_tty_h]),
    ok = case catch control_action(start_app, []) of
             ok -> exit({got_success_but_expected_failure,
                        log_rotation_tty_no_handlers_test});
             {error, {cannot_log_to_tty, _, _}} -> ok
         end,

    %% fix sasl logging
    ok = application:set_env(sasl, sasl_error_logger,
                             {file, SaslLog}),

    %% start application with logging to non-existing directory
    TmpLog = "/tmp/rabbit-tests/test.log",
    delete_file(TmpLog),
    ok = application:set_env(kernel, error_logger, {file, TmpLog}),

    ok = delete_log_handlers([rabbit_error_logger_file_h]),
    ok = add_log_handlers([{error_logger_file_h, MainLog}]),
    ok = control_action(start_app, []),

    %% start application with logging to directory with no
    %% write permissions
    TmpDir = "/tmp/rabbit-tests",
    ok = set_permissions(TmpDir, 8#00400),
    ok = delete_log_handlers([rabbit_error_logger_file_h]),
    ok = add_log_handlers([{error_logger_file_h, MainLog}]),
    ok = case control_action(start_app, []) of
             ok -> exit({got_success_but_expected_failure,
                        log_rotation_no_write_permission_dir_test}); 
            {error, {cannot_log_to_file, _, _}} -> ok
         end,

    %% start application with logging to a subdirectory which
    %% parent directory has no write permissions
    TmpTestDir = "/tmp/rabbit-tests/no-permission/test/log",
    ok = application:set_env(kernel, error_logger, {file, TmpTestDir}),
    ok = add_log_handlers([{error_logger_file_h, MainLog}]),
    ok = case control_action(start_app, []) of
             ok -> exit({got_success_but_expected_failure,
                        log_rotatation_parent_dirs_test});
             {error, {cannot_log_to_file, _,
               {error, {cannot_create_parent_dirs, _, eacces}}}} -> ok
         end,
    ok = set_permissions(TmpDir, 8#00700),
    ok = set_permissions(TmpLog, 8#00600),
    ok = delete_file(TmpLog),
    ok = file:del_dir(TmpDir),

    %% start application with standard error_logger_file_h
    %% handler not installed 
    ok = application:set_env(kernel, error_logger, {file, MainLog}),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),

    %% start application with standard sasl handler not installed
    %% and rabbit main log handler installed correctly
    ok = delete_log_handlers([rabbit_sasl_report_file_h]),
    ok = control_action(start_app, []),
    passed.

test_cluster_management() ->

    %% 'cluster' and 'reset' should only work if the app is stopped
    {error, _} = control_action(cluster, []),
    {error, _} = control_action(reset, []),
    {error, _} = control_action(force_reset, []),

    ok = control_action(stop_app, []),

    %% various ways of creating a standalone node
    NodeS = atom_to_list(node()),
    ClusteringSequence = [[],
                          [NodeS],
                          ["invalid@invalid", NodeS],
                          [NodeS, "invalid@invalid"]],

    ok = control_action(reset, []),
    lists:foreach(fun (Arg) ->
                          ok = control_action(cluster, Arg),
                          ok
                  end,
                  ClusteringSequence),
    lists:foreach(fun (Arg) ->
                          ok = control_action(reset, []),
                          ok = control_action(cluster, Arg),
                          ok
                  end,
                  ClusteringSequence),
    ok = control_action(reset, []),
    lists:foreach(fun (Arg) ->
                          ok = control_action(cluster, Arg),
                          ok = control_action(start_app, []),
                          ok = control_action(stop_app, []),
                          ok
                  end,
                  ClusteringSequence),
    lists:foreach(fun (Arg) ->
                          ok = control_action(reset, []),
                          ok = control_action(cluster, Arg),
                          ok = control_action(start_app, []),
                          ok = control_action(stop_app, []),
                          ok
                  end,
                  ClusteringSequence),

    %% convert a disk node into a ram node
    ok = control_action(reset, []),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),
    ok = control_action(cluster, ["invalid1@invalid",
                                  "invalid2@invalid"]),

    %% join a non-existing cluster as a ram node
    ok = control_action(reset, []),
    ok = control_action(cluster, ["invalid1@invalid",
                                  "invalid2@invalid"]),

    SecondaryNode = rabbit_misc:makenode("hare"),
    case net_adm:ping(SecondaryNode) of
        pong -> passed = test_cluster_management2(SecondaryNode);
        pang -> io:format("Skipping clustering tests with node ~p~n",
                          [SecondaryNode])
    end,

    ok = control_action(start_app, []),
    passed.

test_cluster_management2(SecondaryNode) ->
    NodeS = atom_to_list(node()),
    SecondaryNodeS = atom_to_list(SecondaryNode),

    %% make a disk node
    ok = control_action(reset, []),
    ok = control_action(cluster, [NodeS]),
    %% make a ram node
    ok = control_action(reset, []),
    ok = control_action(cluster, [SecondaryNodeS]),

    %% join cluster as a ram node
    ok = control_action(reset, []),
    ok = control_action(cluster, [SecondaryNodeS, "invalid1@invalid"]),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),

    %% change cluster config while remaining in same cluster
    ok = control_action(cluster, ["invalid2@invalid", SecondaryNodeS]),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),

    %% join non-existing cluster as a ram node
    ok = control_action(cluster, ["invalid1@invalid",
                                  "invalid2@invalid"]),
    %% turn ram node into disk node
    ok = control_action(reset, []),
    ok = control_action(cluster, [SecondaryNodeS, NodeS]),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),
    
    %% convert a disk node into a ram node
    ok = control_action(cluster, ["invalid1@invalid",
                                  "invalid2@invalid"]),

    %% turn a disk node into a ram node
    ok = control_action(reset, []),
    ok = control_action(cluster, [SecondaryNodeS]),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),

    %% NB: this will log an inconsistent_database error, which is harmless
    true = disconnect_node(SecondaryNode),
    pong = net_adm:ping(SecondaryNode),

    %% leaving a cluster as a ram node
    ok = control_action(reset, []),
    %% ...and as a disk node
    ok = control_action(cluster, [SecondaryNodeS, NodeS]),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, []),
    ok = control_action(reset, []),

    %% attempt to leave cluster when no other node is alive
    ok = control_action(cluster, [SecondaryNodeS, NodeS]),
    ok = control_action(start_app, []),
    ok = control_action(stop_app, SecondaryNode, []),
    ok = control_action(stop_app, []),
    {error, {no_running_cluster_nodes, _, _}} =
        control_action(reset, []),

    %% leave system clustered, with the secondary node as a ram node
    ok = control_action(force_reset, []),
    ok = control_action(start_app, []),
    ok = control_action(force_reset, SecondaryNode, []),
    ok = control_action(cluster, SecondaryNode, [NodeS]),
    ok = control_action(start_app, SecondaryNode, []),

    passed.

test_user_management() ->

    %% lots if stuff that should fail
    {error, {no_such_user, _}} =
        control_action(delete_user, ["foo"]),
    {error, {no_such_user, _}} =
        control_action(change_password, ["foo", "baz"]),
    {error, {no_such_vhost, _}} =
        control_action(delete_vhost, ["/testhost"]),
    {error, {no_such_user, _}} =
        control_action(set_permissions, ["foo", ".*", ".*", ".*"]),
    {error, {no_such_user, _}} =
        control_action(clear_permissions, ["foo"]),
    {error, {no_such_user, _}} =
        control_action(list_user_permissions, ["foo"]),
    {error, {no_such_vhost, _}} =
        control_action(list_permissions, ["-p", "/testhost"]),
    {error, {invalid_regexp, _, _}} =
        control_action(set_permissions, ["guest", "+foo", ".*", ".*"]),

    %% user creation
    ok = control_action(add_user, ["foo", "bar"]),
    {error, {user_already_exists, _}} =
        control_action(add_user, ["foo", "bar"]),
    ok = control_action(change_password, ["foo", "baz"]),
    ok = control_action(list_users, []),

    %% vhost creation
    ok = control_action(add_vhost, ["/testhost"]),
    {error, {vhost_already_exists, _}} =
        control_action(add_vhost, ["/testhost"]),
    ok = control_action(list_vhosts, []),

    %% user/vhost mapping
    ok = control_action(set_permissions, ["-p", "/testhost",
                                          "foo", ".*", ".*", ".*"]),
    ok = control_action(set_permissions, ["-p", "/testhost",
                                          "foo", ".*", ".*", ".*"]),
    ok = control_action(list_permissions, ["-p", "/testhost"]),
    ok = control_action(list_user_permissions, ["foo"]),

    %% user/vhost unmapping
    ok = control_action(clear_permissions, ["-p", "/testhost", "foo"]),
    ok = control_action(clear_permissions, ["-p", "/testhost", "foo"]),

    %% vhost deletion
    ok = control_action(delete_vhost, ["/testhost"]),
    {error, {no_such_vhost, _}} =
        control_action(delete_vhost, ["/testhost"]),

    %% deleting a populated vhost
    ok = control_action(add_vhost, ["/testhost"]),
    ok = control_action(set_permissions, ["-p", "/testhost",
                                          "foo", ".*", ".*", ".*"]),
    ok = control_action(delete_vhost, ["/testhost"]),

    %% user deletion
    ok = control_action(delete_user, ["foo"]),
    {error, {no_such_user, _}} =
        control_action(delete_user, ["foo"]),

    passed.

test_server_status() ->

    %% create a queue so we have something to list
    Q = #amqqueue{} = rabbit_amqqueue:declare(
                        rabbit_misc:r(<<"/">>, queue, <<"foo">>),
                        false, false, []),

    %% list queues
    ok = info_action(
           list_queues,
           [name, durable, auto_delete, arguments, pid,
            messages_ready, messages_unacknowledged, messages_uncommitted,
            messages, acks_uncommitted, consumers, transactions, memory],
           true),

    %% list exchanges
    ok = info_action(
           list_exchanges,
           [name, type, durable, auto_delete, arguments],
           true),

    %% list bindings
    ok = control_action(list_bindings, []),

    %% cleanup
    {ok, _} = rabbit_amqqueue:delete(Q, false, false),

    %% list connections
    [#listener{host = H, port = P} | _] =
        [L || L = #listener{node = N} <- rabbit_networking:active_listeners(),
              N =:= node()],

    {ok, C} = gen_tcp:connect(H, P, []),
    timer:sleep(100),
    ok = info_action(
           list_connections,
           [pid, address, port, peer_address, peer_port, state,
            channels, user, vhost, timeout, frame_max,
            recv_oct, recv_cnt, send_oct, send_cnt, send_pend],
           false),
    ok = gen_tcp:close(C),

    passed.

test_hooks() ->
    %% Firing of hooks calls all hooks in an isolated manner
    rabbit_hooks:subscribe(test_hook, test, {rabbit_tests, handle_hook, []}),
    rabbit_hooks:subscribe(test_hook, test2, {rabbit_tests, handle_hook, []}),
    rabbit_hooks:subscribe(test_hook2, test2, {rabbit_tests, handle_hook, []}),
    rabbit_hooks:trigger(test_hook, [arg1, arg2]),
    [arg1, arg2] = get(test_hook_test_fired),
    [arg1, arg2] = get(test_hook_test2_fired),
    undefined = get(test_hook2_test2_fired),

    %% Hook Deletion works
    put(test_hook_test_fired, undefined),
    put(test_hook_test2_fired, undefined),
    rabbit_hooks:unsubscribe(test_hook, test),
    rabbit_hooks:trigger(test_hook, [arg3, arg4]),
    undefined = get(test_hook_test_fired),
    [arg3, arg4] = get(test_hook_test2_fired),
    undefined = get(test_hook2_test2_fired),

    %% Catches exceptions from bad hooks
    rabbit_hooks:subscribe(test_hook3, test, {rabbit_tests, bad_handle_hook, []}),
    ok = rabbit_hooks:trigger(test_hook3, []),

    %% Passing extra arguments to hooks
    rabbit_hooks:subscribe(arg_hook, test, {rabbit_tests, extra_arg_hook, [1, 3]}),
    rabbit_hooks:trigger(arg_hook, [arg1, arg2]),
    {[arg1, arg2], 1, 3} = get(arg_hook_test_fired),

    %% Invoking Pids
    Remote = fun() -> 
        receive 
            {rabbitmq_hook,[remote_test,test,[],Target]} -> 
                Target ! invoked
        end 
    end,
    P = spawn(Remote),
    rabbit_hooks:subscribe(remote_test, test, {rabbit_hooks, notify_remote, [P, [self()]]}),
    rabbit_hooks:trigger(remote_test, []),
    receive
       invoked -> ok
    after 100 ->
       io:format("Remote hook not invoked"),
       throw(timeout)
    end,
    passed.

%---------------------------------------------------------------------

control_action(Command, Args) -> control_action(Command, node(), Args).

control_action(Command, Node, Args) ->
    case catch rabbit_control:action(
                 Command, Node, Args,
                 fun (Format, Args1) ->
                         io:format(Format ++ " ...~n", Args1)
                 end) of
        ok ->
            io:format("done.~n"),
            ok;
        Other -> 
            io:format("failed.~n"),
            Other
    end.

info_action(Command, Args, CheckVHost) ->
    ok = control_action(Command, []),
    if CheckVHost -> ok = control_action(Command, ["-p", "/"]);
       true       -> ok
    end,
    ok = control_action(Command, lists:map(fun atom_to_list/1, Args)),
    {bad_argument, dummy} = control_action(Command, ["dummy"]),
    ok.

empty_files(Files) ->
    [case file:read_file_info(File) of
         {ok, FInfo} -> FInfo#file_info.size == 0;
         Error       -> Error
     end || File <- Files].

non_empty_files(Files) ->
    [case EmptyFile of
         {error, Reason} -> {error, Reason};
         _               -> not(EmptyFile)
     end || EmptyFile <- empty_files(Files)].

test_logs_working(MainLogFile, SaslLogFile) ->
    ok = rabbit_log:error("foo bar"),
    ok = error_logger:error_report(crash_report, [foo, bar]),
    %% give the error loggers some time to catch up
    timer:sleep(50),
    [true, true] = non_empty_files([MainLogFile, SaslLogFile]),
    ok.

set_permissions(Path, Mode) ->
    case file:read_file_info(Path) of
        {ok, FInfo} -> file:write_file_info(
                         Path,
                         FInfo#file_info{mode=Mode});
        Error       -> Error
    end.

clean_logs(Files, Suffix) ->
    [begin
         ok = delete_file(File),
         ok = delete_file([File, Suffix])
     end || File <- Files],
    ok.

delete_file(File) ->
    case file:delete(File) of
        ok              -> ok;
        {error, enoent} -> ok;
        Error           -> Error
    end.

make_files_non_writable(Files) ->
    [ok = file:write_file_info(File, #file_info{mode=0}) ||
        File <- Files],
    ok.

add_log_handlers(Handlers) ->
    [ok = error_logger:add_report_handler(Handler, Args) ||
        {Handler, Args} <- Handlers],
    ok.

delete_log_handlers(Handlers) ->
    [[] = error_logger:delete_report_handler(Handler) ||
        Handler <- Handlers],
    ok.

handle_hook(HookName, Handler, Args) ->
    A = atom_to_list(HookName) ++ "_" ++ atom_to_list(Handler) ++ "_fired",
    put(list_to_atom(A), Args).
bad_handle_hook(_, _, _) ->
    bad:bad().
extra_arg_hook(Hookname, Handler, Args, Extra1, Extra2) ->
    handle_hook(Hookname, Handler, {Args, Extra1, Extra2}).

msg_store_dir() ->
    filename:join(rabbit_mnesia:dir(), "msg_store").

start_msg_store_empty() ->
    start_msg_store(fun (ok) -> finished end, ok).

start_msg_store(MsgRefDeltaGen, MsgRefDeltaGenInit) ->
    rabbit:start_child(rabbit_msg_store, [msg_store_dir(), MsgRefDeltaGen,
                                          MsgRefDeltaGenInit]).

stop_msg_store() ->
    case supervisor:terminate_child(rabbit_sup, rabbit_msg_store) of
        ok -> supervisor:delete_child(rabbit_sup, rabbit_msg_store);
        E -> E
    end.

msg_id_bin(X) ->
    erlang:md5(term_to_binary(X)).

msg_store_contains(Atom, MsgIds) ->
    Atom = lists:foldl(
              fun (MsgId, Atom1) when Atom1 =:= Atom ->
                      rabbit_msg_store:contains(MsgId) end, Atom, MsgIds).

msg_store_sync(MsgIds) ->
    Ref = make_ref(),
    Self = self(),
    ok = rabbit_msg_store:sync(MsgIds,
                               fun () -> Self ! {sync, Ref} end),
    receive
        {sync, Ref} -> ok
    after
        10000 ->
            io:format("Sync from msg_store missing for msg_ids ~p~n", [MsgIds]),
            throw(timeout)
    end.

msg_store_read(MsgIds) ->
    ok =
        lists:foldl(
          fun (MsgId, ok) -> {ok, MsgId} = rabbit_msg_store:read(MsgId), ok end,
          ok, MsgIds).

msg_store_write(MsgIds) ->
    ok = lists:foldl(
           fun (MsgId, ok) -> rabbit_msg_store:write(MsgId, MsgId) end,
           ok, MsgIds).
                            
test_msg_store() ->
    stop_msg_store(),
    ok = start_msg_store_empty(),
    Self = self(),
    MsgIds = [msg_id_bin(M) || M <- lists:seq(1,100)],
    {MsgIds1stHalf, MsgIds2ndHalf} = lists:split(50, MsgIds),
    %% check we don't contain any of the msgs we're about to publish
    false = msg_store_contains(false, MsgIds),
    %% publish the first half
    ok = msg_store_write(MsgIds1stHalf),
    %% sync on the first half
    ok = msg_store_sync(MsgIds1stHalf),
    %% publish the second half
    ok = msg_store_write(MsgIds2ndHalf),
    %% sync on the first half again - the msg_store will be dirty, but
    %% we won't need the fsync
    ok = msg_store_sync(MsgIds1stHalf),
    %% check they're all in there
    true = msg_store_contains(true, MsgIds),
    %% publish the latter half twice so we hit the caching and ref count code
    ok = msg_store_write(MsgIds2ndHalf),
    %% check they're still all in there
    true = msg_store_contains(true, MsgIds),
    %% sync on the 2nd half, but do lots of individual syncs to try
    %% and cause coalescing to happen
    ok = lists:foldl(
           fun (MsgId, ok) -> rabbit_msg_store:sync(
                                [MsgId], fun () -> Self ! {sync, MsgId} end)
           end, ok, MsgIds2ndHalf),
    lists:foldl(
      fun(MsgId, ok) ->
              receive
                  {sync, MsgId} -> ok
              after
                  10000 ->
                      io:format("Sync from msg_store missing (msg_id: ~p)~n",
                                [MsgId]),
                      throw(timeout)
              end
      end, ok, MsgIds2ndHalf),
    %% it's very likely we're not dirty here, so the 1st half sync
    %% should hit a different code path
    ok = msg_store_sync(MsgIds1stHalf),
    %% read them all
    ok = msg_store_read(MsgIds),
    %% read them all again - this will hit the cache, not disk
    ok = msg_store_read(MsgIds),
    %% remove them all
    ok = rabbit_msg_store:remove(MsgIds),
    %% check first half doesn't exist
    false = msg_store_contains(false, MsgIds1stHalf),
    %% check second half does exist
    true = msg_store_contains(true, MsgIds2ndHalf),
    %% read the second half again
    ok = msg_store_read(MsgIds2ndHalf),
    %% release the second half, just for fun (aka code coverage)
    ok = rabbit_msg_store:release(MsgIds2ndHalf),
    %% read the second half again, just for fun (aka code coverage)
    ok = msg_store_read(MsgIds2ndHalf),
    %% read the second half via peruse
    lists:foldl(
      fun (MsgId, ok) ->
              rabbit_msg_store:peruse(MsgId,
                                      fun ({ok, MsgId1}) when MsgId1 == MsgId ->
                                              Self ! {peruse, MsgId1}
                                      end),
              receive
                  {peruse, MsgId} ->
                      ok
              after
                  10000 ->
                      io:format("Failed to receive response via peruse~n"),
                      throw(timeout)
              end
      end, ok, MsgIds2ndHalf),
    %% stop and restart, preserving every other msg in 2nd half
    ok = stop_msg_store(),
    ok = start_msg_store(fun ([]) -> finished;
                             ([MsgId|MsgIdsTail])
                             when length(MsgIdsTail) rem 2 == 0 ->
                                 {MsgId, 1, MsgIdsTail};
                             ([MsgId|MsgIdsTail]) ->
                                 {MsgId, 0, MsgIdsTail}
                         end, MsgIds2ndHalf),
    %% check we have the right msgs left
    lists:foldl(
      fun (MsgId, Bool) ->
              not(Bool = rabbit_msg_store:contains(MsgId))
      end, false, MsgIds2ndHalf),
    %% restart empty
    ok = stop_msg_store(),
    ok = start_msg_store_empty(),
    %% check we don't contain any of the msgs
    false = msg_store_contains(false, MsgIds),
    %% push a lot of msgs in...
    BigCount = 100000,
    MsgIdsBig = lists:seq(1, BigCount),
    Payload = << 0:65536 >>,
    ok = lists:foldl(
           fun (MsgId, ok) ->
                   rabbit_msg_store:write(msg_id_bin(MsgId), Payload)
           end, ok, MsgIdsBig),
    %% .., then remove even numbers ascending, and odd numbers
    %% descending. This hits the GC.
    ok = lists:foldl(
           fun (MsgId, ok) ->
                   rabbit_msg_store:remove([msg_id_bin(
                                              case MsgId rem 2 of
                                                  0 -> MsgId;
                                                  1 -> BigCount - MsgId
                                              end)])
           end, ok, MsgIdsBig),
    %% ensure empty
    false = msg_store_contains(false, [msg_id_bin(M) || M <- MsgIdsBig]),
    %% restart empty
    ok = stop_msg_store(),
    ok = start_msg_store_empty(),
    passed.

queue_name(Name) ->
    rabbit_misc:r(<<"/">>, queue, term_to_binary(Name)).

test_queue() ->
    queue_name(test).

test_amqqueue(Durable) ->
    #amqqueue{name = test_queue(),
              durable = Durable,
              auto_delete = true,
              arguments = [],
              pid = none}.

empty_test_queue() ->
    ok = rabbit_queue_index:start_msg_store([]),
    {0, Qi1} = rabbit_queue_index:init(test_queue()),
    _Qi2 = rabbit_queue_index:terminate_and_erase(Qi1),
    ok.

queue_index_publish(SeqIds, Persistent, Qi) ->
    lists:foldl(
      fun (SeqId, {QiN, SeqIdsMsgIdsAcc}) ->
              MsgId = rabbit_guid:guid(),
              QiM = rabbit_queue_index:write_published(MsgId, SeqId, Persistent,
                                                       QiN),
              ok = rabbit_msg_store:write(MsgId, MsgId),
              {QiM, [{SeqId, MsgId} | SeqIdsMsgIdsAcc]}
      end, {Qi, []}, SeqIds).

verify_read_with_published(_Delivered, _Persistent, [], _) ->
    ok;
verify_read_with_published(Delivered, Persistent,
                           [{MsgId, SeqId, Persistent, Delivered}|Read],
                           [{SeqId, MsgId}|Published]) ->
    verify_read_with_published(Delivered, Persistent, Read, Published);
verify_read_with_published(_Delivered, _Persistent, _Read, _Published) ->
    ko.

test_queue_index() ->
    stop_msg_store(),
    ok = empty_test_queue(),
    SeqIdsA = lists:seq(0,9999),
    SeqIdsB = lists:seq(10000,19999),
    {0, Qi0} = rabbit_queue_index:init(test_queue()),
    {0, 0, Qi1} =
        rabbit_queue_index:find_lowest_seq_id_seg_and_next_seq_id(Qi0),
    {Qi2, SeqIdsMsgIdsA} = queue_index_publish(SeqIdsA, false, Qi1),
    {0, 10000, Qi3} =
        rabbit_queue_index:find_lowest_seq_id_seg_and_next_seq_id(Qi2),
    {ReadA, Qi4} = rabbit_queue_index:read_segment_entries(0, Qi3),
    ok = verify_read_with_published(false, false, ReadA,
                                    lists:reverse(SeqIdsMsgIdsA)),
    %% call terminate twice to prove it's idempotent
    _Qi5 = rabbit_queue_index:terminate(rabbit_queue_index:terminate(Qi4)),
    ok = stop_msg_store(),
    ok = rabbit_queue_index:start_msg_store([test_amqqueue(true)]),
    %% should get length back as 0, as all the msgs were transient
    {0, Qi6} = rabbit_queue_index:init(test_queue()),
    false = rabbit_queue_index:can_flush_journal(Qi6),
    {0, 10000, Qi7} =
        rabbit_queue_index:find_lowest_seq_id_seg_and_next_seq_id(Qi6),
    {Qi8, SeqIdsMsgIdsB} = queue_index_publish(SeqIdsB, true, Qi7),
    {0, 20000, Qi9} =
        rabbit_queue_index:find_lowest_seq_id_seg_and_next_seq_id(Qi8),
    {ReadB, Qi10} = rabbit_queue_index:read_segment_entries(0, Qi9),
    ok = verify_read_with_published(false, true, ReadB,
                                    lists:reverse(SeqIdsMsgIdsB)),
    _Qi11 = rabbit_queue_index:terminate(Qi10),
    ok = stop_msg_store(),
    ok = rabbit_queue_index:start_msg_store([test_amqqueue(true)]),
    %% should get length back as 10000
    LenB = length(SeqIdsB),
    {LenB, Qi12} = rabbit_queue_index:init(test_queue()),
    {0, 20000, Qi13} =
        rabbit_queue_index:find_lowest_seq_id_seg_and_next_seq_id(Qi12),
    Qi14 = lists:foldl(
             fun (SeqId, QiN) ->
                     rabbit_queue_index:write_delivered(SeqId, QiN)
             end, Qi13, SeqIdsB),
    {ReadC, Qi15} = rabbit_queue_index:read_segment_entries(0, Qi14),
    ok = verify_read_with_published(true, true, ReadC,
                                    lists:reverse(SeqIdsMsgIdsB)),
    Qi16 = rabbit_queue_index:write_acks(SeqIdsB, Qi15),
    true = rabbit_queue_index:can_flush_journal(Qi16),
    Qi17 = rabbit_queue_index:flush_journal(Qi16),
    %% the entire first segment will have gone as they were firstly
    %% transient, and secondly ack'd
    SegmentSize = rabbit_queue_index:segment_size(),
    {SegmentSize, 20000, Qi18} =
        rabbit_queue_index:find_lowest_seq_id_seg_and_next_seq_id(Qi17),
    _Qi19 = rabbit_queue_index:terminate(Qi18),
    ok = stop_msg_store(),
    ok = rabbit_queue_index:start_msg_store([test_amqqueue(true)]),
    %% should get length back as 0 because all persistent msgs have been acked
    {0, Qi20} = rabbit_queue_index:init(test_queue()),
    _Qi21 = rabbit_queue_index:terminate_and_erase(Qi20),
    ok = stop_msg_store(),
    ok = empty_test_queue(),
    %% this next bit is just to hit the auto deletion of segment files
    SeqIdsC = lists:seq(0,65535),
    {0, Qi22} = rabbit_queue_index:init(test_queue()),
    {Qi23, _SeqIdsMsgIdsC} = queue_index_publish(SeqIdsC, false, Qi22),
    Qi24 = lists:foldl(
             fun (SeqId, QiN) ->
                     rabbit_queue_index:write_delivered(SeqId, QiN)
             end, Qi23, SeqIdsC),
    Qi25 = rabbit_queue_index:write_acks(SeqIdsC, Qi24),
    {_Oks, {false, Qi26}} =
        rabbit_misc:unfold(
          fun ({true, QiN}) ->
                  QiM = rabbit_queue_index:flush_journal(QiN),
                  {true, ok, {rabbit_queue_index:can_flush_journal(QiM), QiM}};
              ({false, _QiN}) ->
                  false
          end, {true, Qi25}),
    _Qi27 = rabbit_queue_index:terminate_and_erase(Qi26),
    ok = stop_msg_store(),
    ok = rabbit_queue_index:start_msg_store([]),
    ok = stop_msg_store(),
    passed.
