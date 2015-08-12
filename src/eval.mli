(*
 * (c) 2015 Andreas Rossberg
 *)

type module_instance
type value = Types.value

val init : Syntax.modul -> module_instance
val invoke : module_instance -> int -> value list -> value list
  (* raise Error.Error *)
val eval : module_instance -> Syntax.expr -> value (* raise Error.Error *)
