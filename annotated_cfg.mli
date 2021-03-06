(* **
 * Copyright 2013-2016, Inria
 * Suman Saha, Julia Lawall, Gilles Muller, Quentin Lambert
 * This file is part of Hector.

 * Hector is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, according to version 2 of the License.

 * Hector is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with Hector.  If not, see <http://www.gnu.org/licenses/>.

 * The authors reserve the right to distribute this or future versions of
 * Hector under other licenses.
 * *)

module GO = Graph_operations
module Asto = Ast_operations

exception NoCFG

type assignment_operator =
    Simple
  | Algebraic

type assignment = {
  left_value: Ast_c.expression;
  operator: assignment_operator;
  right_value: Asto.assignment;
}

type resource =
    Void     of Ast_c.expression option
  | Resource of Ast_c.expression

type resource_handling =
    Allocation  of resource
  | Assignment  of assignment
  | Release     of resource
  | Computation of Asto.ExpressionSet.t
  | Test        of Asto.ExpressionSet.t
  | Unannotated

type node = {
  is_error_handling: bool;
  resource_handling_type: resource_handling;
  referenced_resources: Asto.ExpressionSet.t;
  parser_node: Control_flow_c.node
}

type edge_type =
    Direct
  | PostBackedge

type edge = {
  start_node: int;
  end_node:   int;
  edge_type:  edge_type;
}

module Key : Set.OrderedType with type t = GO.key
module KeySet : Set.S with type elt = Key.t
module KeyMap : Map.S with type key = Key.t
module Edge : Set.OrderedType with type t = edge
module KeyEdgePair : Set.OrderedType with type t = Key.t * Edge.t
module KeyEdgeSet : Set.S with type elt = KeyEdgePair.t
module G : Ograph_extended.S with
  type key = Key.t and
  type 'a keymap = 'a KeyMap.t and
  type edge = edge and
  type edges = KeyEdgeSet.t

type t = node G.ograph_mutable

val resource_equal: resource -> resource -> bool
val is_void_resource: resource -> bool
val is_similar_statement: node GO.complete_node -> node GO.complete_node -> bool
val is_returning_resource: resource -> node GO.complete_node -> bool
val is_referencing_resource: resource -> node -> bool

val is_on_error_branch:
  (t -> node GO.complete_node -> Ast_c.expression -> Asto.value) ->
  t -> node GO.complete_node -> node -> bool

val get_function_call_name: node GO.complete_node -> string option
val get_arguments: node ->  (Ast_c.expression list) option

val apply_side_effect_visitor:
  (Ast_c.expression -> Ast_c.assignOp option ->
    Ast_c.expression option -> unit) ->
  node -> unit

val apply_assignment_visitor:
  (Ast_c.expression -> Ast_c.assignOp -> Ast_c.expression -> unit) ->
  node -> unit

val is_killing_reach:
  Ast_c.expression -> node -> bool

val is_top_node: node -> bool

val filter_returns: t -> Ast_c.expression -> KeySet.t -> KeySet.t

val test_if_header: (Ast_c.expression -> 'a) -> 'a -> node -> 'a
val test_returned_expression: (Ast_c.expression -> 'a) -> 'a -> node -> 'a

val is_assigning_variable: node GO.complete_node -> bool
val is_non_alloc: node GO.complete_node -> bool
val is_selection: node -> bool

val annotate_resource: t -> node GO.complete_node -> resource_handling -> unit
val get_assignment: node -> assignment option
