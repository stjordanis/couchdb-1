-module(testplan).
-export([start/0]).

-define(FILENAME, "/tmp/vtree.bin").


start() ->
    test_within(),
    test_intersect(),
    test_disjoint(),
    test_lookup(),
    test_area(),
    test_merge_mbr(),
    test_find_area_min_nth(),
    test_partition_node(),
    test_calc_mbr(),
    test_calc_nodes_mbr(),
    test_best_split(),
    test_minimal_overlap(),
    test_minimal_coverage(),
    test_calc_overlap(),
    test_insert(),

    etap:end_tests().


-record(node, {
    % type = inner | leaf
    type=leaf}).

test_insert() ->
    etap:plan(1),

    {ok, Fd} = case couch_file:open(?FILENAME, [create, overwrite]) of
    {ok, Fd2} ->
        {ok, Fd2};
    {error, Reason} ->
        io:format("ERROR (~s): Couldn't open file (~s) for tree storage~n",
                  [Reason, ?FILENAME])
    end,

    Node1 = {{10,5,13,15}, #node{type=leaf}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, #node{type=leaf}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, #node{type=leaf}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, #node{type=leaf}, <<"Node4">>},
    Node5 = {{-5,-16,4,19}, #node{type=leaf}, <<"Node5">>},
    Mbr1 = {10,5,13,15},
    Mbr1_2 = {-18,-3,13,15},
    Mbr1_2_3 = {-21,-3,13,15},
    Mbr1_2_3_4 = {-21,-32,19,15},
    Mbr1_2_3_4_5 = {-21,-32,19,19},
    Mbr1_4_5 = {-5,-32,19,19},
    Mbr2_3 = {-21,-3,-10,14},
    Tree1Node1 = {Mbr1, #node{type=leaf}, [Node1]},
    Tree1Node1_2 = {Mbr1_2, #node{type=leaf}, [Node1, Node2]},
    Tree1Node1_2_3 = {Mbr1_2_3, #node{type=leaf}, [Node1, Node2, Node3]},
    Tree1Node1_2_3_4 = {Mbr1_2_3_4, #node{type=leaf},
                        [Node1, Node2, Node3, Node4]},
    Tree1Node1_2_3_4_5 = {Mbr1_2_3_4_5, #node{type=inner},
                          [{ok, {Mbr2_3, #node{type=leaf}, [Node2, Node3]}},
                           {ok, {Mbr1_4_5, #node{type=leaf},
                                 [Node1, Node4, Node5]}}]},

    etap:is(vtree:insert(Fd, -1, Node1), {ok, Mbr1, 0},
            "Insert a node into an empty tree (write to disk)"),
    etap:is(vtree:get_node(Fd, 0), {ok, Tree1Node1},
            "Insert a node into an empty tree" ++
            " (check if it was written correctly)"),
    {ok, Mbr1_2, Pos2} = vtree:insert(Fd, 0, Node2),
    etap:is(vtree:get_node(Fd, Pos2), {ok, Tree1Node1_2}, 
            "Insert a node into a not yet full leaf node (root node) (a)"),
    {ok, Mbr1_2_3, Pos3} = vtree:insert(Fd, Pos2, Node3),
    etap:is(vtree:get_node(Fd, Pos3), {ok, Tree1Node1_2_3}, 
            "Insert a node into a not yet full leaf node (root node) (b)"),
    {ok, Mbr1_2_3_4, Pos4} = vtree:insert(Fd, Pos3, Node4),
    etap:is(vtree:get_node(Fd, Pos4), {ok, Tree1Node1_2_3_4},
            "Insert a nodes into a then to be full leaf node (root node)"),
    {ok, Mbr1_2_3_4_5, Pos5} = vtree:insert(Fd, Pos4, Node5),
    {ok, {Mbr1_2_3_4_5, #node{type=inner}, [Pos5_1, Pos5_2]}} =
                vtree:get_node(Fd, Pos5),
    etap:is({ok, {Mbr1_2_3_4_5, #node{type=inner},
                  [vtree:get_node(Fd, Pos5_1), vtree:get_node(Fd, Pos5_2)]}},
                  {ok, Tree1Node1_2_3_4_5},
            "Insert a nodes into a full leaf node (root node)"),
    ok.
    

test_within() ->
    etap:plan(4),
    Bbox1 = {-20, -10, 30, 21},
    Bbox2 = {-20, -10, 0, 0},
    Mbr1_2 = {-18,-3,13,15},
    Node1 = {{10,5,13,15}, <<"Node1">>},
    {Node1Mbr, _} = Node1,
    etap:is(vtree:within(Node1Mbr, Bbox1), true, "MBR is within the BBox"),
    etap:is(vtree:within(Node1Mbr, Node1Mbr), true, "MBR is within itself"),
    etap:is(vtree:within(Node1Mbr, Bbox2), false,
            "MBR is not at all within BBox"),
    etap:is(vtree:within(Mbr1_2, Bbox2), false, "MBR intersects BBox"),
    ok.

test_intersect() ->
    etap:plan(17),
    Mbr1_2 = {-18,-3,13,15},
    etap:is(vtree:intersect(Mbr1_2, {-20, -11, 0, 0}), true,
            "MBR intersectton (S and W edge)"),
    etap:is(vtree:intersect(Mbr1_2, {-21, 4, -2, 11}), true,
            "MBR intersecttion (W edge)"),
    etap:is(vtree:intersect(Mbr1_2, {-21, 4, -2, 17}), true,
            "MBR intersection (W and N edge)"),
    etap:is(vtree:intersect(Mbr1_2, {-13, 4, -2, 17}), true,
            "MBR intersection (N edge)"),
    etap:is(vtree:intersect(Mbr1_2, {-13, 4, 16, 17}), true,
            "MBR intersection (N and E edge)"),
    etap:is(vtree:intersect(Mbr1_2, {5, -1, 16, 10}), true,
            "MBR intersection (E edge)"),
    etap:is(vtree:intersect(Mbr1_2, {5, -9, 16, 10}), true,
            "MBR intersection (E and S edge)"),
    etap:is(vtree:intersect(Mbr1_2, {5, -9, 11, 10}), true,
            "MBR intersection (S edge)"),
    etap:is(vtree:intersect(Mbr1_2, {-27, -9, 11, 10}), true,
            "MBR intersection (S and W edge)"),
    etap:is(vtree:intersect(Mbr1_2, {-27, -9, 18, 10}), true,
            "MBR intersection (W and E edge (bottom))"),
    etap:is(vtree:intersect(Mbr1_2, {-27, 2, 18, 10}), true,
            "MBR intersection (W and E edge (middle))"),
    etap:is(vtree:intersect(Mbr1_2, {-10, -9, 18, 10}), true,
            "MBR intersection (W and E edge (top))"),
    etap:is(vtree:intersect(Mbr1_2, {-25, -4, 2, 12}), true, 
            "MBR intersection (N and S edge (left))"),
    etap:is(vtree:intersect(Mbr1_2, {-15, -4, 2, 12}), true,
            "MBR intersection (N and S edge (middle))"),
    etap:is(vtree:intersect(Mbr1_2, {-15, -4, 2, 22}), true,
            "MBR intersection (N and S edge (right))"),
    etap:is(vtree:intersect(Mbr1_2, {-14, -1, 10, 5}), false,
            "One MBR within the other"),
    etap:is(vtree:intersect(Mbr1_2, Mbr1_2), true,
            "MBR is within itself"),
    ok.

test_disjoint() ->
    etap:plan(2),
    Mbr1_2 = {-18,-3,13,15},
    etap:is(vtree:disjoint(Mbr1_2, {27, 20, 38, 40}), true,
            "MBRs are disjoint"),
    etap:is(vtree:disjoint(Mbr1_2, {-27, 2, 18, 10}), false,
            "MBRs are not disjoint").
    

test_lookup() ->
    etap:plan(6),
    Bbox1 = {-20, -10, 30, 21},
    Bbox2 = {-20, -10, 0, 0},
    Bbox3 = {100, 200, 300, 400},
    Bbox4 = {-22, -33, 20, -15},
    Node1 = {{10,5,13,15}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, <<"Node4">>},
    Mbr1_2 = {-18,-3,13,15},
    Mbr1_2_3_4 = {-21,-32,19,15},
    Mbr3_4 = {-21,-32,19,14},
    EmptyTree = {},
    Tree1 = {Mbr1_2, [Node1, Node2]},
    Tree2 = {Mbr1_2_3_4, [{Mbr1_2, [Node1, Node2]}, {Mbr3_4, [Node3, Node4]}]},
    etap:is(vtree:lookup(Bbox1, EmptyTree), {}, "Lookup in empty tree"),
    etap:is(vtree:lookup(Bbox1, Tree1), [Node1, Node2],
            "Find all nodes in tree (tree height=1)"),
    etap:is(vtree:lookup(Bbox2, Tree1), [Node2],
            "Find some nodes in tree (tree height=1)"),
    etap:is(vtree:lookup(Bbox3, Tree1), [],
            "Query window outside of all nodes (tree height=1)"),
    etap:is(vtree:lookup(Bbox2, Tree2), [Node2],
            "Find some nodes in tree (tree height=2) (a)"),
    etap:is(vtree:lookup(Bbox4, Tree2), [Node4],
            "Find some nodes in tree (tree height=2) (b)"),
    etap:is(vtree:lookup(Bbox3, Tree2), [],
            "Query window outside of all nodes (tree height=2)"),
    ok.

test_area() ->
    etap:plan(5),
    Mbr1 = {10,5,13,15},
    Mbr2 = {-18,-3,-10,-1},
    Mbr3 = {-21,2,-10,14},
    Mbr4 = {5,-32,19,-25},
    Mbr5 = {-5,-16,4,19},
    etap:is(vtree:area(Mbr1), 30, "Area of MBR in the NE"),
    etap:is(vtree:area(Mbr2), 16, "Area of MBR in the SW"),
    etap:is(vtree:area(Mbr3), 132, "Area of MBR in the NW"),
    etap:is(vtree:area(Mbr4), 98, "Area of MBR in the SE"),
    etap:is(vtree:area(Mbr5), 315, "Area of MBR covering all quadrants"),
    ok.

test_merge_mbr() ->
    etap:plan(7),
    Mbr1 = {10,5,13,15},
    Mbr2 = {-18,-3,-10,-1},
    Mbr3 = {-21,2,-10,14},
    Mbr4 = {5,-32,19,-25},
    etap:is(vtree:merge_mbr(Mbr1, Mbr2), {-18, -3, 13, 15},
            "Merge MBR of MBRs in NE and SW"),
    etap:is(vtree:merge_mbr(Mbr1, Mbr3), {-21, 2, 13, 15},
            "Merge MBR of MBRs in NE and NW"),
    etap:is(vtree:merge_mbr(Mbr1, Mbr4), {5, -32, 19, 15},
            "Merge MBR of MBRs in NE and SE"),
    etap:is(vtree:merge_mbr(Mbr2, Mbr3), {-21, -3, -10, 14},
            "Merge MBR of MBRs in SW and NW"),
    etap:is(vtree:merge_mbr(Mbr2, Mbr4), {-18, -32, 19, -1},
            "Merge MBR of MBRs in SW and SE"),
    etap:is(vtree:merge_mbr(Mbr3, Mbr4), {-21, -32, 19, 14},
            "Merge MBR of MBRs in NW and SE"),
    etap:is(vtree:merge_mbr(Mbr1, Mbr1), Mbr1,
            "Merge MBR of equal MBRs"),
    ok.

test_find_area_min_nth() ->
    etap:plan(5),
    etap:is(vtree:find_area_min_nth([{5, {23,64,24,79}}]), 1,
            "Find position of minimum area in a list with one element"),
    etap:is(vtree:find_area_min_nth([{538, {2,64,4,79}}, {29, {2,64,4,79}}]), 2,
            "Find position of minimum area in a list with two elements (1>2)"),
    etap:is(vtree:find_area_min_nth([{54, {2,64,4,79}}, {538, {2,64,4,79}}]), 1,
            "Find position of minimum area in a list with two elements (1<2)"),
    etap:is(vtree:find_area_min_nth([{54, {2,64,4,79}}, {54, {2,64,4,79}}]), 1,
            "Find position of minimum area in a list with two equal elements"),
    etap:is(vtree:find_area_min_nth(
              [{329, {2,64,4,79}}, {930, {2,64,4,79}}, {203, {2,64,4,79}},
               {72, {2,64,4,79}}, {402, {2,64,4,79}}, {2904, {2,64,4,79}},
               {283, {2,64,4,79}}]), 4,
            "Find position of minimum area in a list"),
    ok.

test_partition_node() ->
    etap:plan(3),
    Node1 = {{10,5,13,15}, #node{type=leaf}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, #node{type=leaf}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, #node{type=leaf}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, #node{type=leaf}, <<"Node4">>},
    Node5 = {{-5,-16,4,19}, #node{type=leaf}, <<"Node5">>},
    Children3 = [Node1, Node2, Node4],
    Children4 = Children3 ++ [Node3],
    Children5 = Children4 ++ [Node5],
    Mbr1_2_4 = {-18,-25,19,15},
    Mbr1_2_3_4_5 = {-21,-25,19,19},
    etap:is(vtree:partition_node({Mbr1_2_4, #node{type=leaf}, Children3}),
            {[Node2], [Node4], [Node1, Node4], [Node1, Node2]},
            "Partition 3 nodes"),
    etap:is(vtree:partition_node({Mbr1_2_3_4_5, #node{type=leaf}, Children4}),
            {[Node2, Node3], [Node4],
             [Node1, Node4], [Node1, Node2, Node3]},
            "Partition 4 nodes"),
    etap:is(vtree:partition_node({Mbr1_2_3_4_5, #node{type=leaf}, Children5}),
            {[Node2, Node3], [Node4],
             [Node1, Node4, Node5], [Node1, Node2, Node3, Node5]},
            "Partition 5 nodes"),
    ok.


test_calc_mbr() ->
    etap:plan(9),
    Mbr1 = {10,5,13,15},
    Mbr2 = {-18,-3,-10,-1},
    Mbr3 = {-21,2,-10,14},
    Mbr4 = {5,-32,19,-25},
    etap:is(vtree:calc_mbr([]), error,
            "Calculate MBR of an empty list"),
    etap:is(vtree:calc_mbr([Mbr1]), {10, 5, 13, 15},
            "Calculate MBR of a single MBR"),
    etap:is(vtree:calc_mbr([Mbr1, Mbr2]), {-18, -3, 13, 15},
            "Calculate MBR of MBRs in NE and SW"),
    etap:is(vtree:calc_mbr([Mbr1, Mbr3]), {-21, 2, 13, 15},
            "Calculate MBR of MBRs in NE and NW"),
    etap:is(vtree:calc_mbr([Mbr1, Mbr4]), {5, -32, 19, 15},
            "Calculate MBR of MBRs in NE and SE"),
    etap:is(vtree:calc_mbr([Mbr2, Mbr3]), {-21, -3, -10, 14},
            "Calculate MBR of MBRs in SW and NW"),
    etap:is(vtree:calc_mbr([Mbr2, Mbr4]), {-18, -32, 19, -1},
            "Calculate MBR of MBRs in SW and SE"),
    etap:is(vtree:calc_mbr([Mbr3, Mbr4]), {-21, -32, 19, 14},
            "Calculate MBR of MBRs in NW and SE"),
    etap:is(vtree:calc_mbr([Mbr1, Mbr2, Mbr3]), {-21, -3, 13, 15},
            "Calculate MBR of MBRs in NE, SW, NW"),
    etap:is(vtree:calc_mbr([Mbr1, Mbr2, Mbr4]), {-18, -32, 19, 15},
            "Calculate MBR of MBRs in NE, SW, SE"),
    ok.

test_calc_nodes_mbr() ->
    etap:plan(9),
    Node1 = {{10,5,13,15}, #node{type=leaf}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, #node{type=leaf}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, #node{type=leaf}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, #node{type=leaf}, <<"Node4">>},
    etap:is(vtree:calc_nodes_mbr([Node1]), {10, 5, 13, 15},
            "Calculate MBR of a single nodes"),
    etap:is(vtree:calc_nodes_mbr([Node1, Node2]), {-18, -3, 13, 15},
            "Calculate MBR of nodes in NE and SW"),
    etap:is(vtree:calc_nodes_mbr([Node1, Node3]), {-21, 2, 13, 15},
            "Calculate MBR of nodes in NE and NW"),
    etap:is(vtree:calc_nodes_mbr([Node1, Node4]), {5, -32, 19, 15},
            "Calculate MBR of nodes in NE and SE"),
    etap:is(vtree:calc_nodes_mbr([Node2, Node3]), {-21, -3, -10, 14},
            "Calculate MBR of nodes in SW and NW"),
    etap:is(vtree:calc_nodes_mbr([Node2, Node4]), {-18, -32, 19, -1},
            "Calculate MBR of nodes in SW and SE"),
    etap:is(vtree:calc_nodes_mbr([Node3, Node4]), {-21, -32, 19, 14},
            "Calculate MBR of nodes in NW and SE"),
    etap:is(vtree:calc_nodes_mbr([Node1, Node2, Node3]), {-21, -3, 13, 15},
            "Calculate MBR of nodes in NE, SW, NW"),
    etap:is(vtree:calc_nodes_mbr([Node1, Node2, Node4]), {-18, -32, 19, 15},
            "Calculate MBR of nodes in NE, SW, SE"),
    ok.

test_best_split() ->
    etap:plan(4),
    Node1 = {{10,5,13,15}, #node{type=leaf}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, #node{type=leaf}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, #node{type=leaf}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, #node{type=leaf}, <<"Node4">>},
    Node5 = {{-5,-16,4,19}, #node{type=leaf}, <<"Node5">>},
    Node6 = {{-15,10,-12,17}, #node{type=leaf}, <<"Node6">>},
    {Mbr2, _, _} = Node2,
    {Mbr4, _, _} = Node4,
    Mbr1_2 = {-18,-3,13,15},
    Mbr1_4 = {5,-32,19,15},
    Mbr1_4_5 = {-5,-32,19,19},
    Mbr2_3 = {-21,-3,-10,14},
    Mbr4_6 = {-15,-32,19,17},
    Partition3 = {[Node2], [Node4], [Node1, Node4], [Node1, Node2]},
    Partition4 = {[Node2, Node3], [Node4],
                  [Node1, Node4], [Node1, Node2, Node3]},
    Partition5 = {[Node2, Node3], [Node4],
                  [Node1, Node4, Node5], [Node1, Node2, Node3, Node5]},
    Partition4b = {[Node2], [Node4, Node6],
                   [Node1, Node4, Node6], [Node1, Node2]},
    etap:is(vtree:best_split(Partition3), {tie, {Mbr2, Mbr4, Mbr1_4, Mbr1_2}},
            "Best split: tie (3 nodes)"),
    etap:is(vtree:best_split(Partition4), [{Mbr2_3, [Node2, Node3]},
                                           {Mbr1_4, [Node1, Node4]}],
            "Best split: horizontal (W/E) nodes win (4 nodes)"),
    etap:is(vtree:best_split(Partition5), [{Mbr2_3, [Node2, Node3]},
                                           {Mbr1_4_5, [Node1, Node4, Node5]}],
            "Best split: horizontal (W/E) nodes win (5 nodes)"),
    etap:is(vtree:best_split(Partition4b), [{Mbr4_6, [Node4, Node6]},
                                            {Mbr1_2, [Node1, Node2]}],
            "Best split: vertical (S/N) nodes win (4 nodes)"),
    ok.

test_minimal_overlap() ->
    % XXX vmx: test fir S/N split is missing
    etap:plan(2),
    Node1 = {{10,5,13,15}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, <<"Node4">>},
    Node5 = {{-11,-9,12,10}, <<"Node5">>},
    {Mbr2, _} = Node2,
    {Mbr4, _} = Node4,
    Mbr1_2 = {-18,-3,13,15},
    Mbr1_3 = {-21,2,13,15},
    Mbr1_4 = {5,-32,19,15},
    Mbr1_4_5 = {-11,-32,19,15},
    Mbr2_3 = {-21,-3,-10,14},
    Mbr2_4_5 = {-18,-32,19,10},
    Partition3 = {[Node2], [Node4], [Node1, Node4], [Node1, Node2]},
    Partition5 = {[Node2, Node3], [Node2, Node4, Node5],
                  [Node1, Node4, Node5], [Node1, Node3]},
    etap:is(vtree:minimal_overlap(
                Partition5, {Mbr2_3, Mbr2_4_5, Mbr1_4_5, Mbr1_3}),
            [{Mbr2_3, [Node2, Node3]}, {Mbr1_4_5, [Node1, Node4, Node5]}],
            "Minimal Overlap: horizontal (W/E) nodes win (5 Nodes)"),
    etap:is(vtree:minimal_overlap(Partition3, {Mbr2, Mbr4, Mbr1_4, Mbr1_2}),
            tie, "Minimal Overlap: tie"),
    ok.


test_minimal_coverage() ->
    % XXX vmx: test for equal coverage is missing
    etap:plan(2),
    Node1 = {{10,5,13,15}, <<"Node1">>},
    Node2 = {{-18,-3,-10,-1}, <<"Node2">>},
    Node3 = {{-21,2,-10,14}, <<"Node3">>},
    Node4 = {{5,-32,19,-25}, <<"Node4">>},
    Node5 = {{-11,-9,12,10}, <<"Node5">>},
    Node6 = {{-11,-9,12,24}, <<"Node6">>},
    {Mbr4, _} = Node4,
    Mbr1_3 = {-21,2,13,15},
    Mbr1_2_3_6 = {-21,-9,13,24},
    Mbr1_4_5 = {-11,-32,19,15},
    Mbr1_4_6 = {-11,-32,19,24},
    Mbr2_3 = {-21,-3,-10,14},
    Mbr2_4_5 = {-18,-32,19,10},
    Partition5 = {[Node2, Node3], [Node2, Node4, Node5],
                  [Node1, Node4, Node5], [Node1, Node3]},
    Partition6 = {[Node2, Node3], [Node4],
                  [Node1, Node4, Node6], [Node1, Node2, Node3, Node6]},
    etap:is(vtree:minimal_coverage(
                Partition5, {Mbr2_3, Mbr2_4_5, Mbr1_4_5, Mbr1_3}),
            [{Mbr2_3, [Node2, Node3]}, {Mbr1_4_5, [Node1, Node4, Node5]}],
            "Minimal Overlap: horizontal (W/E) nodes win)"),
    etap:is(vtree:minimal_coverage(
                Partition6, {Mbr2_3, Mbr4, Mbr1_4_6, Mbr1_2_3_6}),
            [{Mbr4, [Node4]}, {Mbr1_2_3_6, [Node1, Node2, Node3, Node6]}],
            "Minimal Overlap: vertical (S/N) nodes win"),
    ok.


test_calc_overlap() ->
    etap:plan(7),
    Mbr1 = {10,5,13,15},
    Mbr2 = {-18,-3,-10,-1},
    Mbr3 = {-21,2,-10,14},
    Mbr4 = {5,-32,19,-25},
    Mbr5 = {-11,-9,12,10},
    Mbr6 = {-5,-6,4,9},
    Mbr7 = {4,-11,20,-3},
    etap:is(vtree:calc_overlap(Mbr1, Mbr5), {10, 5, 12, 10},
            "Calculate overlap of MBRs in NE and center"),
    etap:is(vtree:calc_overlap(Mbr2, Mbr5), {-11, -3, -10, -1},
            "Calculate overlap of MBRs in SW and center"),
    etap:is(vtree:calc_overlap(Mbr3, Mbr5), {-11, 2, -10, 10},
            "Calculate overlap of MBRs in NW and center"),
    etap:is(vtree:calc_overlap(Mbr7, Mbr5), {4, -9, 12, -3},
            "Calculate overlap of MBRs in SE and center"),
    etap:is(vtree:calc_overlap(Mbr6, Mbr5), {-5, -6, 4, 9},
            "Calculate overlap of one MBRs enclosing the other (1)"),
    etap:is(vtree:calc_overlap(Mbr5, Mbr6), {-5, -6, 4, 9},
            "Calculate overlap of one MBRs enclosing the other (2)"),
    etap:is(vtree:calc_overlap(Mbr4, Mbr5), {0, 0, 0, 0},
            "Calculate overlap of MBRs with no overlap"),
    ok.
