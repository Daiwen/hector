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

module type KeySet = Set.S with type elt = GO.key

module type Operations =
sig
  type key = GO.key
  type edge
  type keys
  type edges
  type 'node keymap

  type ('node, 'g) readable_graph =
    < nodes: 'node keymap;
      successors:   key -> edges;
      predecessors: key -> edges;
      ..
    > as 'g


  val fold_successors:
    (('node GO.complete_node * edge) -> 'a -> 'a) ->
    ('node, 'g) readable_graph -> key -> 'a -> 'a
end

module type FixPoint =
sig
  type key = GO.key
  type value
  type edge
  type edges
  type 'node keymap

  type ('node, 'g) readable_graph =
    < nodes: 'node keymap;
      successors:   key -> edges;
      predecessors: key -> edges;
      ..
    > as 'g


  module NodeMap : sig
    type key = GO.key
    type 'a t
    val mem:  key -> 'a t -> bool
    val find: key -> 'a t -> 'a
  end

  type ('node, 'g, 'res) configuration =
    {get_next_nodes:
       ('node, 'g) readable_graph ->
       ('node GO.complete_node * edge) list ->
       'node GO.complete_node -> ('node GO.complete_node * edge) list;

     update_value:
       value NodeMap.t -> ('node GO.complete_node * edge) -> value;

     compute_result:
       value NodeMap.t -> ('node GO.complete_node * edge) ->
       'res -> 'res;
     (* **
      * This function compute the new result from visited_nodes,
      * the current node and the current result value
      * *)

     predicate: value NodeMap.t -> ('node GO.complete_node * edge) -> bool;
     (* **
      * The predicate is called with visited_nodes as first argument and
      * the algorithm only fold on the node if predicate returns true
      * *)

     initial_value:  value;
     initial_result: 'res;
    }

  val get_forward_config:
    (value NodeMap.t -> ('node GO.complete_node * edge) -> value) ->
    (value NodeMap.t -> ('node GO.complete_node * edge) ->
     'res -> 'res) ->
    (value NodeMap.t -> ('node GO.complete_node * edge) -> bool) ->
    value -> 'res ->
    ('node, 'g, 'res) configuration

  val get_backward_config:
    (value NodeMap.t -> ('node GO.complete_node * edge) -> value) ->
    (value NodeMap.t -> ('node GO.complete_node * edge) ->
     'res -> 'res) ->
    (value NodeMap.t -> ('node GO.complete_node * edge) -> bool) ->
    value -> 'res ->
    ('node, 'g, 'res) configuration

  val compute:
    ('node, 'g, 'res) configuration ->
    ('node, 'g) readable_graph ->
    'node GO.complete_node -> 'res
end

module Make (KS : KeySet) (Ops : Operations)
    (FP : FixPoint with
       type key          = Ops.key and
       type value        = bool and
       type edge         = Ops.edge and
       type edges        = Ops.edges and
       type 'node keymap = 'node Ops.keymap) =
struct
  type ('node, 'g) readable_graph =
    < nodes: 'node Ops.keymap;
      successors:   Ops.key -> Ops.edges;
      predecessors: Ops.key -> Ops.edges;
      ..
    > as 'g

  let build_basic_config get_config predicate initial_result =
    get_config predicate
      (fun visited_nodes (s, _) res ->
         if FP.NodeMap.mem  s.GO.index visited_nodes &&
            FP.NodeMap.find s.GO.index visited_nodes
         then
           KS.add s.GO.index res
         else
           res)
       predicate true initial_result

  let get_basic_forward_config  predicate initial_result =
    build_basic_config FP.get_forward_config  predicate initial_result

  let get_basic_backward_config predicate initial_result =
    build_basic_config FP.get_backward_config predicate initial_result

  let conditional_get_post_dominated p g cn =
    let predicate set (n, e) =
      p (n, e) &&
      Ops.fold_successors
        (fun (cn, _) acc -> acc &&
                            (FP.NodeMap.mem  cn.GO.index set &&
                             FP.NodeMap.find cn.GO.index set))
        g n.GO.index true
    in
    let config =
      get_basic_backward_config predicate (KS.singleton cn.GO.index)
    in
    FP.compute config g cn
end
