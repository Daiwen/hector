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
module ACFG = Annotated_cfg

type exemplar = {
  alloc: ACFG.node GO.complete_node;
  alloc_name: string;
  release: ACFG.node GO.complete_node;
  release_name: string;
  res: ACFG.resource;
}
type fault = {
  exemplar: exemplar;
  block_head: ACFG.node GO.complete_node;
}

val find_errorhandling:
  ACFG.t -> (ACFG.node GO.complete_node) list

val get_exemplars:
  ACFG.t -> (ACFG.node GO.complete_node) list -> exemplar list

val get_faults:
  ACFG.t -> (ACFG.node GO.complete_node) list -> exemplar -> fault list
