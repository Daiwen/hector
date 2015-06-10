(*
 * Copyright 2013, Inria
 * Suman Saha, Julia Lawall, Gilles Muller
 * This file is part of Hector.
 *
 * Hector is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, according to version 2 of the License.
 *
 * Hector is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Hector.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The authors reserve the right to distribute this or future versions of
 * Hector under other licenses.
 *)

open Common

let ref_var_mark = ref false

(**************Find and gather code from label *********)

let rec code_for_goto name = function
     []->[]
  |  (label,code)::t -> if (Def.compare_names label name)
                             then  (if(Def.inner_blk code) then [] else code )
	                else code_for_goto name t


let rec gather_goto_code lbl_list goto_code = function
  []-> goto_code
  | h::t->
          (match Ast_c.unwrap h with
              Ast_c.Jump (Ast_c.Return) -> (goto_code@[h])
           |  Ast_c.Jump (Ast_c.ReturnExpr e) -> (goto_code@[h])
           |  Ast_c.Jump (Ast_c.Goto name) -> if (not(Errorhandling.goto_jump_toback h lbl_list)) then
                                                  let new_goto_code = code_for_goto name lbl_list in 
						     if (List.length new_goto_code) = 0 then gather_goto_code lbl_list [] []
                                                     else
                                                        gather_goto_code lbl_list goto_code new_goto_code
                                              else gather_goto_code lbl_list [] []
           | _-> gather_goto_code lbl_list (goto_code@[h]) t
          )


(**************Is return statement access the resource  *********)


let rec find_ptr_args_list = function
  []->[]
  |   h::t-> match (Def.is_pointer h) with
             Def.IsPtr->h::find_ptr_args_list t
         |   Def.UnknownType-> h::find_ptr_args_list t
         |   _-> find_ptr_args_list t

let rec find_final_return = function
  [] -> 1000000
  | h::t-> match Ast_c.unwrap h with
             Ast_c.Jump (Ast_c.Return) -> Def.find_startline_no (Def.create_stmtlist h)
           | Ast_c.Jump (Ast_c.ReturnExpr e) -> Def.find_startline_no (Def.create_stmtlist h)
           | _-> find_final_return t

let rec any_exp_exists_in_stmt stmt = function
  []-> false
  | h::t-> if (Def.exp_exists_in_stmt (Some h) stmt) then true
          else any_exp_exists_in_stmt stmt t

let rec exp_exists_in_stmtlist exp = function
  []-> false
  | h::t-> if (Def.exp_exists_in_stmt exp h) then true 
           else exp_exists_in_stmtlist exp t

let rec create_stmtlist = function
  []->[]
  | h::t-> ((Ast_c.ExprStatement (Some h),[]))::(create_stmtlist t)


let rec return_st_access_resource lbl_list miss_st  = function
  []-> false
  | h::t-> (match Ast_c.unwrap h with
              Ast_c.Jump (Ast_c.ReturnExpr e1) -> 
                 ( match Ast_c.unwrap miss_st with
                     Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii))->
                       let args_list = Def.remove_optionlist (Def.create_argslist [] es) in
                       let args_stmtlist = create_stmtlist (find_ptr_args_list args_list) in
                          if (List.length args_list = 0) then false
                          else if (any_exp_exists_in_stmt h args_list) || 
			            (exp_exists_in_stmtlist (Some e1) args_stmtlist) 
		   	         then true
                          else false
                   | _ -> false              
                 )
            | Ast_c.Jump (Ast_c.Goto name) -> let goto_code = gather_goto_code lbl_list [] [h]  in
                                                  if (List.length goto_code)=0 then true
                                                  else return_st_access_resource lbl_list miss_st goto_code 
            | _-> return_st_access_resource lbl_list miss_st  t
           )



let rec function_return_same_val return_val = function
  []-> false
  | h::t-> (match Ast_c.unwrap h with
               Ast_c.Jump (Ast_c.ReturnExpr e1) -> if (Def.compare_exps return_val e1) then true
		                                   else function_return_same_val return_val t
             | _-> function_return_same_val return_val t )


let rec stmtlist_func_contains_same_val return_val = function
   []-> false 
  | h::t-> ( match Ast_c.unwrap h with
               Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii))-> 
		  let args_list = Def.remove_optionlist (Def.create_argslist [] es) in
		  if (Def.exp_exists_in_list return_val args_list) then true
                  else stmtlist_func_contains_same_val return_val t
              |_-> stmtlist_func_contains_same_val return_val t 		   
           )

let rec other_errblk_contains_same_val return_val = function
    []-> false
  | (brnch_strtlineno,test_case,st_normal,goto,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
      if (stmtlist_func_contains_same_val return_val stmtlist) then true
      else other_errblk_contains_same_val return_val t
  


let rec remove_blks_that_returns_resource prog errblks= function
    []->[]
  |  (brnch_strtlineno,test_case,goto,st_normal,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
      ( match (Def.return_exists_in_list stmtlist) with
          None-> remove_blks_that_returns_resource prog errblks t
      |	  Some (Ast_c.Jump (Ast_c.ReturnExpr e1),ii)-> if (function_return_same_val e1 prog)  then(
	                                                  match (Def.is_pointer e1) with
                                                          | Def.UnknownType-> remove_blks_that_returns_resource prog errblks t
							  | Def.IsPtr->       remove_blks_that_returns_resource prog errblks t
                                                          | Def.IsntPtr-> (brnch_strtlineno,test_case,goto,st_normal, typ,blk_strtlineno,blk_endlineno,stmtlist)::
							                   (remove_blks_that_returns_resource prog errblks t)
                                                          | _-> remove_blks_that_returns_resource prog errblks t
																	  
                                                          )
	                                               else if (other_errblk_contains_same_val e1 errblks) then
							       remove_blks_that_returns_resource prog errblks t
	                                               else (brnch_strtlineno,test_case,goto,st_normal,typ,blk_strtlineno,blk_endlineno,stmtlist)::
	                                                    (remove_blks_that_returns_resource prog errblks t)
      |	  _-> (brnch_strtlineno,test_case,goto,st_normal,typ,blk_strtlineno,blk_endlineno,stmtlist)::(remove_blks_that_returns_resource prog errblks t)
      )



let rec return_resource_new lbl_list errblk miss_rr_ops_list  = function
  []-> miss_rr_ops_list
  | (alloc,args,h)::t-> if (return_st_access_resource lbl_list h errblk) then
                           return_resource_new lbl_list errblk miss_rr_ops_list t
                        else return_resource_new lbl_list errblk ((alloc,args,h)::miss_rr_ops_list)  t





(* Ranking *)


let rec any_exp_exists_in_list args_list2 = function
  []-> false
  | h::t-> if (Def.exp_exists_in_list h args_list2) then true
           else  any_exp_exists_in_list args_list2 t



let rec ranking args_list1 upper lower miss_line   lbl_list  rrl = function
   []-> (upper,lower)
  |  h::t-> match Ast_c.unwrap h with
    |   Ast_c.Labeled (Ast_c.Label (name, st)) ->
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |  (a,b) -> ranking args_list1 a b miss_line  lbl_list  rrl t)
    |   Ast_c.Labeled (Ast_c.Case  (e, st)) ->
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b miss_line  lbl_list  rrl t)


    |   Ast_c.Labeled (Ast_c.CaseRange  (e, e2, st)) ->
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b miss_line  lbl_list  rrl t)



    |   Ast_c.Labeled (Ast_c.Default st) ->
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b miss_line  lbl_list  rrl t)



    |   Ast_c.Compound statxs -> 
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist h)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    |   Ast_c.ExprStatement (Some (((Ast_c.Cast    (ty, (((Ast_c.FunCall  (e3, es3)), typ1), ii1))), typ), ii))->

           let args_list2 = Def.remove_optionlist (Def.create_argslist [] es3) in
           let line_no = Def.find_startline_no (Def.create_stmtlist h) in
           if (any_exp_exists_in_list args_list2 args_list1) then
               if line_no < miss_line then
                  ranking args_list1 true lower  miss_line  lbl_list  rrl t
               else ranking args_list1 upper true  miss_line  lbl_list  rrl t
           else ranking args_list1 upper lower  miss_line  lbl_list  rrl t


    |   Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e3, es3)), typ), ii)) ->

           let args_list2 = Def.remove_optionlist (Def.create_argslist [] es3) in
           let line_no = Def.find_startline_no (Def.create_stmtlist h) in 
           if (List.length args_list1) = 0 && (Def.compare_stmts rrl h) then(
	     if line_no < miss_line then 
	       (
                  print_string(string_of_int(miss_line));
                 ranking args_list1 true lower  miss_line  lbl_list  rrl t)
             else (
                     print_string(string_of_int(miss_line));

                    ranking args_list1 upper true  miss_line  lbl_list  rrl t)
	   )  
	   else if (any_exp_exists_in_list args_list2 args_list1) then
               if line_no < miss_line then
                  ranking args_list1 true lower  miss_line  lbl_list  rrl t
               else ranking args_list1 upper true  miss_line  lbl_list  rrl t
           else ranking args_list1 upper lower  miss_line  lbl_list  rrl t
   
    |   Ast_c.ExprStatement (Some e) -> ranking args_list1 upper lower  miss_line  lbl_list  rrl t
    |   Ast_c.Selection  (Ast_c.If (e, st1, st2)) ->
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist st1)) with
           (true,true)-> (true,true)
        |    (a,b) -> ( match (ranking args_list1 a b  miss_line  lbl_list  rrl (Def.create_stmtlist st2)) with
                          (true,true)-> (true,true)
	                | (a1,b1) -> ranking args_list1 a1 b1  miss_line  lbl_list  rrl t

                      )
        )


    |   Ast_c.Selection  (Ast_c.Switch (e, st)) ->
        (match (ranking args_list1 upper lower  miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    |   Ast_c.Iteration  (Ast_c.While (e, st)) ->
        (match (ranking args_list1 upper lower  miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    |   Ast_c.Iteration  (Ast_c.DoWhile (st, e)) ->
        (match (ranking args_list1 upper lower  miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    | Ast_c.Iteration  (Ast_c.For (Ast_c.ForDecl _,(e2opt,il2),(e3opt, il3),st11)) ->
	failwith "for loop with declaration in first argument not supported"
    |   Ast_c.Iteration  (Ast_c.For (Ast_c.ForExp(e1opt,il1),(e2opt,il2),(e3opt, il3),st)) ->
        (match (ranking args_list1 upper lower miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    |   Ast_c.Iteration  (Ast_c.MacroIteration (s,es,st)) ->
        (match (ranking args_list1 upper lower  miss_line  lbl_list  rrl (Def.create_stmtlist st)) with
           (true,true)-> (true,true)
        |   (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    |   Ast_c.Jump (Ast_c.Goto name) -> 
                        let goto_code = gather_goto_code lbl_list [] [h]  in
			(match (ranking args_list1 upper lower  miss_line  lbl_list  rrl goto_code) with
                           (true,true)-> (true,true)
                        |  (a,b) -> ranking args_list1 a b  miss_line  lbl_list  rrl t)

    |   Ast_c.Jump ((Ast_c.Continue|Ast_c.Break)) -> ranking args_list1 upper lower  miss_line  lbl_list  rrl t

    |   Ast_c.Jump (Ast_c.Return) -> ranking args_list1 upper lower  miss_line  lbl_list  rrl []
    |   Ast_c.Jump (Ast_c.ReturnExpr e) -> ranking args_list1 upper lower  miss_line  lbl_list  rrl []
    |   Ast_c.Jump (Ast_c.GotoComputed e) -> ranking args_list1 upper lower  miss_line  lbl_list  rrl t
    |   Ast_c.Decl decl -> ranking args_list1 upper lower  miss_line  lbl_list  rrl t
    |   Ast_c.Asm asmbody -> ranking args_list1 upper lower  miss_line  lbl_list  rrl t
    |   Ast_c.NestedFunc def -> ranking args_list1 upper lower  miss_line  lbl_list  rrl t
    |   _ ->  ranking args_list1 upper lower  miss_line  lbl_list  rrl t




let rec find_ranking_main blk_strtlineno prog  lbl_list = function
  []-> []
  | (alloc,args,rrl)::t-> 
      let (upper,lower) = ranking args false false blk_strtlineno  lbl_list  rrl prog in
      (match (upper, lower) with
	(true, true) -> (alloc,args,rrl,Def.Hr)::(find_ranking_main blk_strtlineno prog  lbl_list t)
      |	(true, false) -> (alloc,args,rrl,Def.Mr)::(find_ranking_main blk_strtlineno prog  lbl_list t)
      |	(false, true) -> (alloc,args,rrl,Def.Lr)::(find_ranking_main blk_strtlineno prog  lbl_list t)
      |	(_,_)-> (alloc,args,rrl,Def.No)::(find_ranking_main blk_strtlineno prog  lbl_list t)

      )







let rec refine_ref_list args_list = function
   []-> []
  | (a,b)::t->
              if(Def.compare_exps a (List.hd args_list)) then (a,b)::(refine_ref_list args_list t)
              else refine_ref_list args_list t


let rec any_ref_var_access_stmt args_list = function
  []-> false
  | h::t->
          match h with 
             (((Ast_c.Ident (Ast_c.RegularName("NULL",ii2))), typ), ii)-> any_ref_var_access_stmt args_list t
           |_->
              if (Def.exp_exists_in_list h args_list) then (true)
              else (any_ref_var_access_stmt args_list t)

let rec any_var_access_stmt args_list = function
  []-> false
  | (var,ref_vars)::t-> 
                     if (Def.exp_exists_in_list var args_list) then (ref_var_mark:= false; true)
                     else if  any_ref_var_access_stmt args_list ref_vars then ((*print_string("\nTrue Inner\n");*) ref_var_mark:= true; true)
                     else any_var_access_stmt args_list t


let rec fn_exists_in_list = function
  []-> false
  | h::t->
           (match Ast_c.unwrap h with
               Common.Left es -> (match  es with
                                    (((Ast_c.FunCall  (e, es1)), typ), ii)-> true
                                   |(((Ast_c.SizeOfExpr  (e)), typ), ii)-> true
                                   | (((Ast_c.SizeOfType  (t)), typ), ii)-> true
                                   | _ ->  fn_exists_in_list t )
             | _ -> fn_exists_in_list t
            )

let rec rls_by_getref vars = function
  []-> false 
  | h::t-> 
           match h with
           | (((Ast_c.Unary (e, Ast_c.GetRef)), typ), ii)->
	                                                   if (Def.exp_exists_in_list e vars) then true
		                                           else rls_by_getref vars t

           |_-> rls_by_getref vars t 

let rec rls_by_getref_outer args_list = function
  []-> false
  | (a,b)::t-> if (rls_by_getref b args_list ) then true
               else rls_by_getref_outer args_list t


let rec find_last_access var ref_vars last_access = function
  []-> last_access
  | h::t-> 
      match Ast_c.unwrap h with
            Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e3, es3)), typ), ii)) ->
	      let args_list = Def.remove_optionlist (Def.create_argslist [] es3) in
              if (not(Def.string_exists_in_stmt h)) && (not(fn_exists_in_list es3))then (
	         if (Def.exp_exists_in_list var args_list) then(
		    ref_var_mark:= false;
		    find_last_access var ref_vars (Some h) t)
                 else if (any_var_access_stmt args_list ref_vars) then(
   	            find_last_access var ref_vars (Some h) t)
                 else if (match var with
		            (((Ast_c.RecordAccess   (e, name)), typ), ii)->
			                                                    if (Def.compare_exps var e) then true
									    else if (rls_by_getref [e] args_list) then (ref_var_mark:= true; true)
				                                            else false
                         |  (((Ast_c.RecordPtAccess   (e, name)), typ), ii)-> 
			                                                      if (Def.compare_exps var e) then true
				                                              else false  
                         | _-> false
                 ) then find_last_access var ref_vars (Some h) t
                 else if (rls_by_getref_outer args_list ref_vars)  then ( ref_var_mark:= true; find_last_access var ref_vars (Some h) t)
                 else if (rls_by_getref [var] args_list) then (ref_var_mark:= false; find_last_access var ref_vars (Some h) t)
                 else find_last_access var ref_vars last_access t)
              else find_last_access var ref_vars last_access t
          | Ast_c.ExprStatement (Some  ((( Ast_c.Assignment (e1, op, 
		    (((Ast_c.CondExpr ( ((( Ast_c.FunCall  
                     ((((Ast_c.Ident (Ast_c.RegularName("IS_ERR",ii4))), typ3), ii3), es10)), typ2), ii2), e2, e3)), typ1), ii1))), typ), ii))->

             let args_list10 = Def.remove_optionlist (Def.create_argslist [] es10)  in 
              if (Def.exp_exists_in_list var args_list10) then ( ref_var_mark:= false;

                      find_last_access var ref_vars (Some h) t)
              else if (any_var_access_stmt args_list10 ref_vars) then(  
		find_last_access var ref_vars (Some h) t)  
	      else  find_last_access var ref_vars last_access t
								 

          | Ast_c.ExprStatement (Some (((Ast_c.Assignment (e1, op, ((Ast_c.FunCall  (e3, es3), typ1), ii1))), typ2), ii2)) ->
              let args_list = Def.remove_optionlist (Def.create_argslist [] es3) in
	      if (Def.exp_exists_in_list var args_list) then ( ref_var_mark:= false;
		      find_last_access var ref_vars (Some h) t)
              else if (any_var_access_stmt args_list ref_vars) then(
                find_last_access var ref_vars (Some h) t)
              else find_last_access var ref_vars last_access t
          | _->
	      if (Def.exp_exists_in_stmt (Some var) h) then (
	            find_last_access var ref_vars None  t)
                else find_last_access var ref_vars last_access t


let rec stmt_exists_in_list st = function
    []-> false
  |  h::t -> if (Def.find_startline_no [st]) = (Def.find_startline_no [h])  then true
            else stmt_exists_in_list st t


let rec stmt_exists_in_any_list st = function
     []-> false
  |    h::t -> if(stmt_exists_in_list st h) then true
              else  stmt_exists_in_any_list st t


let rec rr_in_exe_paths_init_lbl rls lbl_list prog last_func blk_strtlineno = function
    []-> false
  | stmtlist::t->
      if(Def.stmt_exists_in_list rls stmtlist) then
                        let exe_paths_list = Errorhandling.generate_exe_paths_simple (blk_strtlineno-1) [] lbl_list prog in
			if(stmt_exists_in_any_list last_func exe_paths_list) then true
			else rr_in_exe_paths_init_lbl rls lbl_list prog last_func blk_strtlineno t
       else rr_in_exe_paths_init_lbl rls lbl_list prog last_func blk_strtlineno t


let rec rr_in_exe_paths_new rls lbl_list prog last_func = function
  []->false
  | (brnch_strtlineno,test_case,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
         if(Def.stmt_exists_in_list rls stmtlist) then
                        let exe_paths_list = Errorhandling.generate_exe_paths_simple (blk_strtlineno-1) [] lbl_list prog in
                         if(stmt_exists_in_any_list last_func exe_paths_list) then true
			 else rr_in_exe_paths_new rls lbl_list prog last_func t
         else rr_in_exe_paths_new rls lbl_list prog last_func t

let rec stmt_exists_in_list st = function
  []-> false
  | h::t-> if (Def.compare_stmts st h) && (not(Def.string_exists_in_stmt h)) then true
           else stmt_exists_in_list st t

let rec release_by_address arg = function
  []-> false
  | h::t->  
           match h with 
           | (((Ast_c.Unary (e, Ast_c.GetRef)), typ), ii)-> 
	                                          if (Def.compare_exps arg e) then true
		                                  else
	                                          (
						   match e with
						     ((( Ast_c.RecordAccess   (e, name)), typ1), ii1)-> if(Def.compare_exps arg e) then true 
							                                                else release_by_address arg t
						   | ((( Ast_c.RecordPtAccess   (e, name)), typ1), ii1)->if(Def.compare_exps arg e) then true
							                                                else release_by_address arg t
						   | _->release_by_address arg t
						  )

           | _-> release_by_address arg t



let rec is_locally_dec branch_lineno = function
 []-> false
  | h::t-> 
            let start_line = Def.find_startline_no (Def.create_stmtlist h) in
            let end_line = Def.find_endline_no (Def.create_stmtlist h) in
            if (branch_lineno>= start_line && branch_lineno<=end_line) then true
            else is_locally_dec branch_lineno t


let rec is_locally_main branch_lineno name local = function
  [] -> local
  | h::t-> 
               match Ast_c.unwrap h with
	       |  Ast_c.Labeled (Ast_c.Label (name, st)) ->
		   let new_local = 
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t
	       |  Ast_c.Labeled (Ast_c.Case  (e, st)) -> 
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t
	       |  Ast_c.Labeled (Ast_c.CaseRange  (e, e2, st)) ->
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t
	       |  Ast_c.Labeled (Ast_c.Default st) -> 
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t
	       |  Ast_c.Compound statxs -> 
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist h) in
                   is_locally_main branch_lineno name new_local t

	       |  Ast_c.Selection  (Ast_c.If (e, st1, st2)) ->
		   let new_local1 =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st1) in
		   let new_local2 =
                   is_locally_main branch_lineno name new_local1 (Def.create_stmtlist st1) in
                   is_locally_main branch_lineno name new_local2 t

	       |  Ast_c.Selection  (Ast_c.Switch (e, st)) ->
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t

	       |  Ast_c.Iteration  (Ast_c.While (e, st)) -> 
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t

	       |  Ast_c.Iteration  (Ast_c.DoWhile (st, e)) -> 
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t

	       | Ast_c.Iteration  (Ast_c.For (Ast_c.ForDecl _,(e2opt,il2),(e3opt, il3),st11)) ->
		   failwith "for loop with declaration in first argument not supported"
	       |  Ast_c.Iteration  (Ast_c.For (Ast_c.ForExp(e1opt,il1),(e2opt,il2),(e3opt, il3),st)) ->  
		   let new_local =
                   is_locally_main branch_lineno name local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local  t

	       |  Ast_c.Iteration  (Ast_c.MacroIteration (s,es,st)) -> 
		   let new_local =
                   is_locally_main branch_lineno name  local (Def.create_stmtlist st) in
                   is_locally_main branch_lineno name new_local t

               |   Ast_c.Decl decl -> (
                                   match decl with
                                       Ast_c.DeclList decls ->
                                        (match Ast_c.unwrap decls with
                                           [one] ->

                                             let onedecl = Ast_c.unwrap2 one in
                                                (match onedecl.Ast_c.v_namei with
                                                   Some(nm,vl) -> if (Def.compare_names nm name) then( 
                                                                     if (is_locally_dec branch_lineno t) then (
								       is_locally_main branch_lineno name true t)
								     else (is_locally_main branch_lineno name false t))
                                                                  else is_locally_main branch_lineno name local t

                                                |   None-> is_locally_main branch_lineno name local t)
                                        |  _-> is_locally_main branch_lineno name local t
                                         )
                                     | _-> is_locally_main branch_lineno name local t
                                )


	       |  _ -> is_locally_main branch_lineno name local t






let rec any_exp_exists_in_stmtlist_inner arg = function
  []-> false
  | h::t-> match Ast_c.unwrap h with
             Ast_c.ExprStatement (Some ((( Ast_c.FunCall  (e, es)), typ), ii)) -> 
	       if (not(Def.string_exists_in_stmt h)) then
		   let args_list = Def.remove_optionlist (Def.create_argslist [] es) in
		   if (Def.exp_exists_in_list arg args_list) then true
                   else if (release_by_address arg args_list) then true
                   else any_exp_exists_in_stmtlist_inner arg t
               else any_exp_exists_in_stmtlist_inner arg t
             | Ast_c.ExprStatement (Some (((Ast_c.Assignment (e1, op, e2)), typ), ii)) ->
		 if(Def.compare_exps arg e1) then true
                 else any_exp_exists_in_stmtlist_inner arg t
             | _-> any_exp_exists_in_stmtlist_inner arg t

let rec any_exp_exists_in_stmtlist stmtlist = function
  []-> false
  | h::t-> if(any_exp_exists_in_stmtlist_inner h stmtlist) then true
           else any_exp_exists_in_stmtlist stmtlist t

let any_alloc alloc =
  match Ast_c.unwrap alloc with
  | Ast_c.ExprStatement (Some ((( Ast_c.FunCall  ((((Ast_c.Ident (Ast_c.RegularName(id,ii3))), typ1), ii1), es)), typ), ii))->
        if Errorhandling.defined_alloc id then true else false
  | _-> false



let rec rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list = function
  []->list
  | (alloc,args,rr)::t->  
          match Ast_c.unwrap rr with
            Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) ->
              let final_return = find_final_return prog in
	      let args_list = find_ptr_args_list (Def.remove_optionlist (Def.create_argslist [] es)) in
              let reg_alloc = Str.regexp "[a-z0-9_]+" in 
              if (match alloc with 
                  (Ast_c.ExprStatement (Some (((Ast_c.FunCall  (((( Ast_c.Ident (Ast_c.RegularName(id,ii2))), typ1), ii1), es)), typ), ii)),ii4)  
                     when  
                       Str.string_match  reg_alloc id 0 -> false
                     | _ -> true

                  | _-> true) then (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)

              else if(List.length args_list) = 0 then
                 (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t)
              else if (List.length args)= 0 then(
                rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)

              else if (      
                      match (List.hd args_list) with     
                        (((Ast_c.Ident (ident)), typ10), ii10) -> let local = is_locally_main branch_lineno ident true prog in if local = true  then (false) else (true)

                      | (((Ast_c.RecordAccess  ((((Ast_c.Ident (ident)), typ11), ii11), name)), typ10), ii10) ->
			  let local = is_locally_main branch_lineno ident true prog in if local = true  then (false) else (true)
                      | (((Ast_c.RecordPtAccess  ((((Ast_c.Ident (ident)), typ11), ii11), name)), typ10), ii10) -> 
			  let local = is_locally_main branch_lineno ident true prog   in

			 if local = true  then (false) else (true)
                      | _->false
 		    )  then rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t

              else if (Def.stmt_exists_in_list rr stmtlist) then (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)
             
	      else if (any_exp_exists_in_stmtlist stmtlist args) then ( rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)

              else if (any_alloc alloc) then 
		(rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)

              else ( 
		
                let fin_lineno = branch_lineno in
                let exe_paths_lists = Errorhandling.generate_exe_paths_simple fin_lineno [] lbl_list prog in

                let rec check_each_path = function
                   []->  if !ref_var_mark = false then 
		     (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)
		         else (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)
                  | path::rest-> 
                        let t_ref_vars = Pointer_linked.gather_all_ref_var [] path in
                        let ref_vars = refine_ref_list args t_ref_vars in
                        let last_access = find_last_access (List.hd args) ref_vars None path in
                        let tmp = 
                  	  if (Def.exp_exists_in_stmt (Some (List.hd args)) (Ast_c.ExprStatement (Some test_case),[])) then ( 
                             match test_case with
                               (((Ast_c.Binary   (((( Ast_c.ParenExpr ((((Ast_c.Assignment (e1, op, e2)), typ1), ii1))), typ2), ii2), op1, e3)), typ3), ii3) -> 
				let follow = (Errorhandling.is_following_code_access_exp (((List.hd args_list),[])::ref_vars )
                                                                    branch_lineno false final_return prog) in 

                                if follow == false then (true)
                                else false
                            |_-> false )
                             else false in
                           if tmp = true then (
                                      rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)
                           else 
                             match last_access with
                               None-> if(List.length rest)= 0 then 
			                 (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t)
                                      else check_each_path rest
                             | Some access->   
			          (match Ast_c.unwrap access with
                                     Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e3, es3)), typ), ii)) ->
			               if alloc = access then
                                         (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t)
				         else if (Def.compare_stmts rr access) then
							rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t
                                         else if (stmt_exists_in_list access stmtlist) && !ref_var_mark = false then 
                                                        rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t

                                         else if (stmt_exists_in_list access stmtlist) && !ref_var_mark = true then
                                                        rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t
                                                      
                                         else if (rr_in_exe_paths_new rr lbl_list prog access errblk_list) then
                                                      (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t)
                                         else if (rr_in_exe_paths_init_lbl rr lbl_list prog access (Def.find_startline_no init_lbl_list) [init_lbl_list] ) then
                                                      (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t)
                                         else check_each_path rest
										 
			             | Ast_c.ExprStatement (Some (((Ast_c.Assignment (e1, op, ((Ast_c.FunCall  (e3, es3), typ1), ii1))), typ2), ii2)) ->
				         if (stmt_exists_in_list access stmtlist) then
							rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t
                                         else if (Def.exp_exists_in_stmt (Some e1) (Ast_c.ExprStatement (Some test_case),[])) then (
					   let local =
                                              ((Errorhandling.is_following_code_access_exp  (((List.hd args),[])::ref_vars )  
								    branch_lineno false final_return prog))  in 
                                           if local = false (* && (List.length errblk_list) = 1 *)then(
						rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t)
							  
					   else							   
      					        (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t))
					   else if (rr_in_exe_paths_new rr lbl_list prog access errblk_list) then
					       (rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list ((alloc,args,rr)::list) t)

					   else check_each_path rest

                                     | Ast_c.ExprStatement (Some (((Ast_c.Assignment (e1, op, ((( Ast_c.CondExpr
                                           ((((( Ast_c.FunCall  ((((Ast_c.Ident (Ast_c.RegularName("IS_ERR",ii5))),
							       typ4), ii4), es10)), typ3), ii3)), e2, e3)), typ1), ii1))), typ2), ii2)) ->
                                                                let args_list10 = Def.remove_optionlist (Def.create_argslist [] es10)  in
                                                                if(Def.compare_exps (List.hd args_list10) (List.hd args)) then
                                                                 rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t
								else check_each_path rest

                                     | _-> check_each_path rest

                                         )
                       in check_each_path exe_paths_lists       
                                         
                                         
              )        
          | _-> rls_in_exe_paths branch_lineno lbl_list prog errblk_list test_case stmtlist init_lbl_list list t





let rec find_all_poss_alloc args_list = function
    []->[]
  |  h::t-> match Ast_c.unwrap h with
             Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) ->

               let args_list1 = Def.create_argslist [] es in
               if (List.length args_list1) > 0 && (Def.compare_explists (Def.remove_optionlist args_list1) (Def.remove_optionlist args_list)) then(
                  h::(find_all_poss_alloc args_list t))
               else find_all_poss_alloc args_list t
    | _-> find_all_poss_alloc args_list t


let rec find_all_poss_alloc_main args_list poss_list = function
   []-> poss_list
  |  h::t-> let tmp_list = find_all_poss_alloc args_list h in
           if(List.length tmp_list) > 0 then
              find_all_poss_alloc_main args_list (tmp_list::poss_list) t
           else find_all_poss_alloc_main args_list poss_list t


let rec find_all_rrwa = function
    []->[]
  | h::t-> match Ast_c.unwrap h with
             Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) ->
	       let args_list = Def.create_argslist [] es in
               if (List.length args_list) = 0 then
                  h::(find_all_rrwa t)
               else find_all_rrwa t
             |_-> find_all_rrwa t 

let rec find_all_rrwa_main rrwa_list = function
   []-> rrwa_list
  | h::t-> let tmp_list = find_all_rrwa h in
           if(List.length tmp_list) > 0 then
	      find_all_rrwa_main (tmp_list::rrwa_list) t
           else find_all_rrwa_main rrwa_list t

             


let rec make_pairs list1 list2 pairs_list= 
  match (list1, list2) with
    (h::t, h1::t1)-> if(not(Def.compare_stmts h h1)) then make_pairs t t1 ([(h,h1)]@pairs_list)
	             else make_pairs t t1  pairs_list
  | ([],_)-> pairs_list
  | (_, [])->pairs_list


let rec find_alloc_op miss_st = function
    []-> None
  | (alloc,rr)::t-> if(Def.compare_stmts rr miss_st) then (Some alloc)
                    else find_alloc_op miss_st t



let rec find_first_model_blk miss_st mergin model = function
     []->model
  |  (brnch_strtlineno,test_case,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
        if(Def.stmt_exists_in_list miss_st stmtlist) then
            if (blk_strtlineno < mergin) then
               find_first_model_blk miss_st blk_strtlineno (Some (blk_strtlineno, stmtlist)) t
            else find_first_model_blk miss_st mergin model t
         else find_first_model_blk miss_st mergin model t



let rec find_model_blk_init_lbl miss_st = function
     []->None
  |   stmtlist::t->
        if(Def.stmt_exists_in_list miss_st stmtlist) then
          (Some ((Def.find_startline_no stmtlist), stmtlist))
	else find_model_blk_init_lbl miss_st t



let rec find_model_blk miss_st = function
     []->(0,[])
  |  (brnch_strtlineno,test_case,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
        if(Def.stmt_exists_in_list miss_st stmtlist) then
	  (blk_strtlineno, stmtlist)
        else find_model_blk miss_st t


let rec find_app_model_blk miss_st diff model model_line miss_blk = function
     []->(model_line, model)
  |  (brnch_strtlineno,test_case,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
      if(Def.stmt_exists_in_list miss_st stmtlist) then
          if (miss_blk - blk_strtlineno) < 0 && diff = 0 then (blk_strtlineno, stmtlist)
  	  else if (miss_blk - blk_strtlineno) > diff then find_app_model_blk miss_st (miss_blk - blk_strtlineno) stmtlist blk_strtlineno miss_blk t
  	  else find_app_model_blk miss_st diff model model_line miss_blk t
      else find_app_model_blk miss_st diff model model_line miss_blk t



 

let rec find_common_rrwa_in_model_path_inner list = function
  []->[]
  | h::t-> if(Def.stmt_exists_in_all_list h list) then
             h::(find_common_rrwa_in_model_path_inner list t)
           else find_common_rrwa_in_model_path_inner list t


let find_common_rrwa_in_model_path = function
  []->[]
  | h::t-> (find_common_rrwa_in_model_path_inner  t h)


let rec rem_brn_st_frm_list_inner st = function
  []-> false
  | h::t-> if(Def.compare_stmts h st) && (Def.find_startline_no [h]) = (Def.find_startline_no [st]) then
             true
           else rem_brn_st_frm_list_inner st t

let rec rem_brn_st_frm_list all_rrwa_in_model_branch = function
  []-> []
  | h::t-> if(rem_brn_st_frm_list_inner h all_rrwa_in_model_branch) then
             rem_brn_st_frm_list all_rrwa_in_model_branch t
           else h::(rem_brn_st_frm_list all_rrwa_in_model_branch t)


         




let rec is_rrwa_alloc errblk_list miss_blk miss_blk_st_line miss_rr_ops_list lbl_list prog = function
  [] ->  miss_rr_ops_list
  | (alloc,args,rls)::t-> 
      match Ast_c.unwrap rls with
	Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) -> 
	  let args_list = Def.create_argslist [] es in
            if (List.length args_list) = 0 then
              begin
		let (model_blk_st_no, model_blk) = find_app_model_blk rls 0 [] 0 miss_blk_st_line errblk_list in
                let all_rrwa_in_model = find_all_rrwa model_blk in 

                let exe_paths = Errorhandling.generate_exe_paths_simple model_blk_st_no [] lbl_list prog in
                let all_rrwa_in_model_path = find_all_rrwa_main [] exe_paths in

                let common_rrwa_in_model_path = find_common_rrwa_in_model_path all_rrwa_in_model_path in

                let common_rrwa_in_model_path = rem_brn_st_frm_list all_rrwa_in_model common_rrwa_in_model_path in
                let pairs_list = make_pairs common_rrwa_in_model_path (List.rev all_rrwa_in_model) [] in
                let alloc_op = find_alloc_op rls pairs_list in
                  begin
                    match alloc_op with
                      None-> 
                           is_rrwa_alloc errblk_list miss_blk  miss_blk_st_line  miss_rr_ops_list lbl_list prog t
                    | Some a-> 
                           let exe_paths_list =  Errorhandling.generate_exe_paths_simple (miss_blk_st_line-1) []  lbl_list prog  in
                           if any_alloc a then is_rrwa_alloc errblk_list miss_blk  miss_blk_st_line miss_rr_ops_list lbl_list prog t
                           else if(Def.stmt_exists_in_all_list a exe_paths_list) && (not(Def.stmt_exists_in_all_list rls exe_paths_list))then
                              is_rrwa_alloc errblk_list miss_blk  miss_blk_st_line ((a,args,rls)::miss_rr_ops_list) lbl_list prog t
                           else is_rrwa_alloc errblk_list miss_blk  miss_blk_st_line miss_rr_ops_list lbl_list prog t
                  end
              end
            else is_rrwa_alloc errblk_list miss_blk  miss_blk_st_line ((alloc,args,rls)::miss_rr_ops_list) lbl_list prog t





 let rec no_previous_blk_has_rrl miss_line rrl alloc_line = function
    []-> []
    | (brnch_strtlineno,test_case,typ,blk_strtlineno,blk_endlineno,stmtlist)::t->
        if blk_strtlineno > alloc_line && blk_endlineno < miss_line && (not(Def.stmt_exists_in_list rrl stmtlist)) then(
 	blk_strtlineno::(no_previous_blk_has_rrl miss_line rrl alloc_line t))
        else no_previous_blk_has_rrl miss_line rrl alloc_line t


let rec stmt_exists_in_exe_paths_inner stmt = function
  []-> false
  | h::t -> if (Def.compare_stmts h stmt) then true
            else stmt_exists_in_exe_paths_inner stmt t

let rec stmt_exists_in_exe_paths stmt = function
  []-> false
  | h::t-> if stmt_exists_in_exe_paths_inner stmt h then true
           else stmt_exists_in_exe_paths stmt t

 let rec find_actual_alloc exe_paths_model exe_paths_candidate = function
  []-> None
  | h::t->  
           match Ast_c.unwrap h with 
             Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) ->
	       if (stmt_exists_in_exe_paths h exe_paths_model) && (not(stmt_exists_in_exe_paths h exe_paths_candidate))then
                   (Some h) 
               else find_actual_alloc exe_paths_model exe_paths_candidate t
           | _-> find_actual_alloc exe_paths_model exe_paths_candidate t


let rec resource_is_not_allocated_yet errblks miss_line prog lbl_list miss_rr_ops_list = function
  []-> miss_rr_ops_list
  |   (alloc,args,rrl)::t->
         let alloc_line = Def.find_startline_no (Def.create_stmtlist alloc) in
         match Ast_c.unwrap rrl with
	   Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) ->
	   let args_list = Def.create_argslist [] es in

	   if (List.length args_list) = 1 then 
            ( 
	      let lines = no_previous_blk_has_rrl miss_line rrl alloc_line errblks in 
              if (List.length lines) > 0 then
                let (model_blk_st_no, model_blk) = find_app_model_blk rrl 0 [] 0 miss_line errblks in 
	        let exe_paths_model = Errorhandling.generate_exe_paths_simple (model_blk_st_no-1) [] lbl_list prog in 
		let exe_paths_candidate  = Errorhandling.generate_exe_paths_simple miss_line [] lbl_list prog in

                let all_pos_alloc_can = find_all_poss_alloc_main args_list [] exe_paths_model in 

		let common_alloc = find_common_rrwa_in_model_path all_pos_alloc_can in 

                let actual_alloc = find_actual_alloc exe_paths_model exe_paths_candidate common_alloc  in 

		  begin   
		    match actual_alloc with 
		      None -> resource_is_not_allocated_yet errblks miss_line prog lbl_list ((alloc,args,rrl)::miss_rr_ops_list) t
		    | Some a -> 
			resource_is_not_allocated_yet errblks miss_line prog lbl_list miss_rr_ops_list t
                  end 
              else resource_is_not_allocated_yet errblks miss_line prog lbl_list ((alloc,args,rrl)::miss_rr_ops_list) t 
	   )else resource_is_not_allocated_yet errblks miss_line prog lbl_list ((alloc,args,rrl)::miss_rr_ops_list) t 

	 | _-> resource_is_not_allocated_yet errblks miss_line prog lbl_list miss_rr_ops_list t




let rec find_idvalues_list exe_paths_list id_values= function
  []->id_values
  | h::t-> 
             let new_id_values = (Errorhandling.find_recent_id_values_paths_second h [] exe_paths_list) in             
             if(List.length new_id_values)>0 then
	       if (List.length id_values) = 0 then
                  (find_idvalues_list exe_paths_list new_id_values t)
               else []
             else find_idvalues_list exe_paths_list id_values t


let rec same_id_values_inner st = function
  []-> true
  | h::t-> if(Def.compare_exps st h) then same_id_values_inner st t
           else false

let rec same_id_values list = function
  []-> true
  | h::t-> if(same_id_values_inner h list) then
              same_id_values list t
           else false


let rec refine_id_values_inner = function
  []-> []
  | h::t-> match h with
            (((Ast_c.Ident (Ast_c.RegularName("NULL",ii2))), typ), ii)-> refine_id_values_inner t
           |_-> h::(refine_id_values_inner t)  

let rec refine_id_values list =  function
  []-> list
  | h::t-> let tmp = refine_id_values_inner h in
           if (List.length tmp)> 0 then refine_id_values (tmp::list) t
           else refine_id_values list t

let rec is_resource_having_same_def_new func_name iifunc1 miss_list branch_lineno lbl_list prog errblk_list init_lbl_list = function
  []-> miss_list
  | (alloc,args_list,h)::t-> 
          let reg_alloc = Str.regexp "[A-Z0-9_]+" in
          match Ast_c.unwrap h with
	    Ast_c.ExprStatement (Some (((Ast_c.FunCall  (e, es)), typ), ii)) -> 
               if(List.length args_list)>0 then         
                  let fin_lineno = branch_lineno in
		  let exe_paths_list = Errorhandling.generate_exe_paths_simple fin_lineno [] lbl_list prog in
                  let ids_list1 = Def.refine_id_list (Errorhandling.list_of_id_values exe_paths_list args_list) in
		  let id_values1 = if(List.length args_list) =1 then Errorhandling.find_recent_id_values_paths (List.hd args_list) [] exe_paths_list
			           else (find_idvalues_list exe_paths_list [] args_list) in
                  let id_values1 = 
                         if (same_id_values id_values1 id_values1) && (List.length id_values1) !=0 then [(List.hd id_values1)] else [] in 
                  let id_values1 = refine_id_values_inner id_values1 in
  


                  let (model_blk_st_no, model_blk) = 
		    match find_first_model_blk h 10000000 None errblk_list with 
		      Some (model_blk_st_no, model_blk) -> (model_blk_st_no, model_blk)
		    | None -> (match find_model_blk_init_lbl h  [init_lbl_list] with
			         Some (model_blk_st_no, model_blk) -> (model_blk_st_no, model_blk)
		               | None ->  (0, [])
			      ) 
                  in 

                  let fin_lineno = model_blk_st_no  in

                  let exe_paths_list = Errorhandling.generate_exe_paths_simple (fin_lineno-1) [] lbl_list prog   in

                  let ids_list2 = Def.refine_id_list(Errorhandling.list_of_id_values exe_paths_list args_list) in

                  let id_values2 = if(List.length args_list) =1 then Errorhandling.find_recent_id_values_paths (List.hd args_list) [] exe_paths_list
                                   else find_idvalues_list exe_paths_list [] args_list in
  

                  let id_values2 = refine_id_values_inner id_values2 in
  
                  let id_values2 =
                     if (same_id_values id_values2 id_values2 ) && (List.length id_values2) !=0 then [(List.hd id_values2)] else [] in 

                  let unique_id_values = if(List.length id_values1)=1 && (List.length id_values2)=1 then 
	                            	       Def.unique_id_values ids_list1 ids_list2 ids_list1 
                                         else [] in

		     
                  if(List.length unique_id_values)= 1 then 
		       (is_resource_having_same_def_new func_name iifunc1 (((Ast_c.ExprStatement (Some (List.hd unique_id_values)),[]),args_list,h)::miss_list)
	      											 branch_lineno lbl_list prog  errblk_list init_lbl_list t)
                  else is_resource_having_same_def_new func_name iifunc1 miss_list branch_lineno lbl_list prog  errblk_list init_lbl_list t

               else (is_resource_having_same_def_new func_name iifunc1 
                      ((alloc,args_list,h)::miss_list) branch_lineno lbl_list prog   errblk_list init_lbl_list t)
          | _-> is_resource_having_same_def_new func_name iifunc1 miss_list branch_lineno lbl_list prog errblk_list init_lbl_list t



