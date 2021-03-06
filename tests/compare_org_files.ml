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

module OrderedPairs =
struct
  type t = string * string
  let compare (a, _) (b, _) = compare a b
end

module StringPairSet = Set.Make(OrderedPairs)

let read_file filename combine init =
  let input_line' chan =
    try
      let first_line  = input_line chan in
      let second_line = input_line chan in
      Some (first_line, second_line)
    with End_of_file -> None
  in
  let chan = open_in filename in
  let rec read lines =
    match input_line' chan with
    | None -> lines
    | Some line -> read (combine line lines)
  in let result = read init in
  close_in chan;
  result

(** Command line arguments **)
let first_file  = Sys.argv.(1)
let second_file = Sys.argv.(2)
(****************************)

let first_output  = read_file first_file  StringPairSet.add StringPairSet.empty
let second_output = read_file second_file StringPairSet.add StringPairSet.empty

let () =
  Printf.printf "%B\n%!" (StringPairSet.equal first_output second_output);

  if StringPairSet.equal first_output second_output
  then
      ()
  else
    let diff_result = StringPairSet.diff first_output second_output in
    let print_string_couple (a, _) =
      Printf.eprintf "%s\n%!" a
    in
    StringPairSet.iter print_string_couple diff_result
