extends GutTest

## The node editor compiles to assembly rather than executing anything of its
## own. These check that the two views really cannot disagree.


func _graph(nodes: Array, entry: String = "n1") -> Dictionary:
	return {"entry": entry, "nodes": nodes}


func test_a_linear_graph_compiles_and_assembles() -> void:
	var program := (
		NodeGraph
		. compile(
			_graph(
				[
					{"id": "n1", "type": "throttle", "value": 1, "next": "n2"},
					{
						"id": "n2",
						"type": "burn_until",
						"lhs": "ALT",
						"cmp": ">",
						"rhs": 10000,
						"next": "n3"
					},
					{"id": "n3", "type": "halt"},
				]
			)
		)
	)
	assert_true(program.ok(), program.first_error_text())
	assert_eq(program.source_kind, Program.SOURCE_NODES)
	assert_false(program.node_graph.is_empty(), "the graph is kept for the editor")


func test_the_emitted_text_is_what_actually_runs() -> void:
	var graph := _graph(
		[
			{"id": "n1", "type": "throttle", "value": 0.5, "next": "n2"},
			{"id": "n2", "type": "burn", "seconds": 30, "next": "n3"},
			{"id": "n3", "type": "halt"},
		]
	)
	var from_graph := NodeGraph.compile(graph)
	var emitted: Dictionary = NodeGraph.emit_source(graph)
	var from_text := Assembler.assemble(String(emitted["source"]))
	assert_eq(
		from_graph.content_hash(),
		from_text.content_hash(),
		"a graph and its text form must be the same program"
	)


func test_a_branch_emits_a_conditional_skip_and_a_jump() -> void:
	var program := (
		NodeGraph
		. compile(
			_graph(
				[
					{
						"id": "n1",
						"type": "branch",
						"lhs": "APO",
						"cmp": "<",
						"rhs": 100000,
						"true": "n2",
						"false": "n3"
					},
					{"id": "n2", "type": "burn", "seconds": 1, "next": "n1"},
					{"id": "n3", "type": "halt"},
				]
			)
		)
	)
	assert_true(program.ok(), program.first_error_text())
	var text := program.to_text()
	assert_string_contains(text, "IF APO < 100000")
	assert_string_contains(text, "JMP")


func test_a_loop_back_edge_resolves() -> void:
	var program := (
		NodeGraph
		. compile(
			_graph(
				[
					{"id": "loop", "type": "burn", "seconds": 0.5, "next": "check"},
					{
						"id": "check",
						"type": "branch",
						"lhs": "ALT",
						"cmp": "<",
						"rhs": 5000,
						"true": "loop",
						"false": "done"
					},
					{"id": "done", "type": "halt"},
				],
				"loop"
			)
		)
	)
	assert_true(program.ok(), program.first_error_text())


func test_node_ids_never_collide_as_labels() -> void:
	# "a-b" and "a_b" would both sanitise to the same name if labels were
	# derived from the id rather than from position.
	var program := (
		NodeGraph
		. compile(
			_graph(
				[
					{"id": "a-b", "type": "throttle", "value": 1, "next": "a_b"},
					{"id": "a_b", "type": "halt"},
				],
				"a-b"
			)
		)
	)
	assert_true(program.ok(), program.first_error_text())


func test_a_dangling_edge_still_compiles() -> void:
	# A player wiring a graph up should never be shown a broken program just
	# because they have not finished yet.
	var program := (
		NodeGraph
		. compile(
			_graph(
				[
					{"id": "n1", "type": "throttle", "value": 1, "next": "nowhere"},
				]
			)
		)
	)
	assert_true(program.ok(), program.first_error_text())


func test_a_node_with_no_successor_ends_the_program() -> void:
	var program := (
		NodeGraph
		. compile(
			_graph(
				[
					{"id": "n1", "type": "throttle", "value": 1},
				]
			)
		)
	)
	assert_true(program.ok(), program.first_error_text())
	assert_string_contains(program.to_text(), "HALT")


func test_an_unreachable_node_is_reported_but_not_fatal() -> void:
	var emitted: Dictionary = (
		NodeGraph
		. emit_source(
			_graph(
				[
					{"id": "n1", "type": "halt"},
					{"id": "orphan", "type": "burn", "seconds": 1},
				]
			)
		)
	)
	var errors: Array = emitted["errors"]
	assert_gt(errors.size(), 0, "the player should be told the node is stranded")
	assert_string_contains(String(errors[0]["message"]).to_lower(), "reach")


func test_an_unknown_node_type_is_named() -> void:
	var emitted: Dictionary = (
		NodeGraph
		. emit_source(
			_graph(
				[
					{"id": "n1", "type": "frobnicate"},
				]
			)
		)
	)
	var errors: Array = emitted["errors"]
	assert_gt(errors.size(), 0)
	assert_string_contains(String(errors[0]["message"]), "frobnicate")


func test_a_duplicate_node_id_is_refused() -> void:
	var emitted: Dictionary = (
		NodeGraph
		. emit_source(
			_graph(
				[
					{"id": "n1", "type": "halt"},
					{"id": "n1", "type": "halt"},
				]
			)
		)
	)
	assert_gt(emitted["errors"].size(), 0)


func test_an_empty_graph_does_not_crash() -> void:
	var emitted: Dictionary = NodeGraph.emit_source({"entry": "", "nodes": []})
	assert_eq(String(emitted["source"]), "")


func test_arithmetic_nodes_cover_the_isa() -> void:
	var nodes: Array = []
	var i := 1
	for type in NodeGraph.ARITH_TYPES:
		var value = "ALT" if type == "sense" else 1
		nodes.append(
			{
				"id": "n%d" % i,
				"type": type,
				"register": "R0",
				"value": value,
				"next": "n%d" % (i + 1)
			}
		)
		i += 1
	nodes.append({"id": "n%d" % i, "type": "halt"})
	var program := NodeGraph.compile(_graph(nodes))
	assert_true(program.ok(), program.first_error_text())


func test_a_linear_graph_can_be_built_from_steps() -> void:
	# Mission Control uses this to hand back something editable as a graph.
	var graph := (
		NodeGraph
		. linear_graph(
			[
				{"type": "throttle", "value": 1},
				{"type": "burn", "seconds": 10},
				{"type": "halt"},
			]
		)
	)
	var program := NodeGraph.compile(graph)
	assert_true(program.ok(), program.first_error_text())
	assert_eq(program.instruction_count(), 3)
