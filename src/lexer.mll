(*
 * (c) 2015 Andreas Rossberg
 *)

{
open Parser
open Types
open Syntax

let convert_pos pos =
  { Source.file = pos.Lexing.pos_fname;
    Source.line = pos.Lexing.pos_lnum;
    Source.column = pos.Lexing.pos_cnum - pos.Lexing.pos_bol
  }

let region lexbuf =
  let left = convert_pos (Lexing.lexeme_start_p lexbuf) in
  let right = convert_pos (Lexing.lexeme_end_p lexbuf) in 
  {Source.left = left; Source.right = right}

let error lexbuf m = Error.error (region lexbuf) m
let error_nest start lexbuf m =
  lexbuf.Lexing.lex_start_p <- start;
  error lexbuf m

let convert_escape = function
  | 'n' -> '\n'
  | 't' -> '\t'
  | '\\' -> '\\'
  | '\'' -> '\''
  | '\"' -> '\"'
  | _ -> assert false

let convert_text s =
  let b = Buffer.create (String.length s) in
  let i = ref 1 in
  while !i < String.length s - 1 do
    Buffer.add_char b
      (if s.[!i] <> '\\' then s.[!i] else (incr i; convert_escape s.[!i]));
    incr i
  done;
  Buffer.contents b

let value_type = function
  | "i32" -> Int32Type
  | "i64" -> Int64Type
  | "f32" -> Float32Type
  | "f64" -> Float64Type
  | _ -> assert false

let mem_type s t =
  let open Memory in
  match s, t with
  | 's', "i8" -> SInt8Mem
  | 's', "i16" -> SInt16Mem
  | 's', "i32" -> SInt32Mem
  | 's', "i64" -> SInt64Mem
  | 'u', "i8" -> UInt8Mem
  | 'u', "i16" -> UInt16Mem
  | 'u', "i32" -> UInt32Mem
  | 'u', "i64" -> UInt64Mem
  | ' ', "f32" -> Float32Mem
  | ' ', "f64" -> Float64Mem
  | _ -> assert false

module I32 = Int32Op
module I64 = Int64Op
module F32 = Float32Op
module F64 = Float64Op

let intop t i32 i64 =
  match t with
  | "i32" -> Int32 i32
  | "i64" -> Int64 i64
  | _ -> assert false

let floatop t f32 f64 =
  match t with
  | "f32" -> Float32 f32
  | "f64" -> Float64 f64
  | _ -> assert false

let memop d a s t =
  let dist = match d with
    | "near" -> Near
    | "far" -> Far
    | _ -> assert false
  and align = match a with
    | "" -> Memory.Aligned
    | "unaligned" -> Memory.Unaligned
    | _ -> assert false
  in {dist; align; mem = mem_type s t}
}


let space = [' ''\t']
let digit = ['0'-'9']
let letter = ['a'-'z''A'-'Z']
let symbol = ['+''-''*''/''\\''^''~''=''<''>''!''?''@''#''$''%''&''|'':''`']
let tick = '\''
let escape = ['n''t''\\''\'''\"']
let character = [^'"''\\''\n'] | '\\'escape

let num = ('+' | '-')? digit+
let int = num
let float = (num '.' digit+) | num ('e' | 'E') num
let text = '"' character* '"'
let atom = (letter | digit | '_' | tick | symbol)*

let ixx = "i" ("32" | "64")
let fxx = "f" ("32" | "64")
let nxx = ixx | fxx
let mixx = "i" ("8" | "16" | "32" | "64")
let mfxx = "f" ("32" | "64")
let sign = "s" | "u"
let dist = "near" | "far"
let align = "" | "unaligned"

rule token = parse
  | "(" { LPAR }
  | ")" { RPAR }
  | int as s { INT s }
  | float as s { FLOAT s }
  | text as s { TEXT (convert_text s) }
  | '"'character*('\n'|eof) { error lexbuf "unclosed text literal" }
  | '"'character*'\\'_
    { error_nest (Lexing.lexeme_end_p lexbuf) lexbuf "illegal escape" }

  | "i32" { TYPE Int32Type }
  | "i64" { TYPE Int64Type }
  | "f32" { TYPE Float32Type }
  | "f64" { TYPE Float64Type }

  | "nop" { NOP }
  | "block" { BLOCK }
  | "if" { IF }
  | "loop" { LOOP }
  | "label" { LABEL }
  | "break" { BREAK }
  | "switch" { SWITCH }
  | "case" { CASE }
  | "fallthru" { FALLTHRU }
  | "call" { CALL }
  | "dispatch" { DISPATCH }
  | "return" { RETURN }
  | "destruct" { DESTRUCT }

  | "getlocal" { GETLOCAL }
  | "setlocal" { SETLOCAL }
  | "getglobal" { GETGLOBAL }
  | "setglobal" { SETGLOBAL }

  | "get"(dist as d)(align as a)(sign as s)"."(mixx as t)
    { GETMEMORY (memop d a s t) }
  | "set"(dist as d)(align as a)(sign as s)"."(mixx as t)
    { SETMEMORY (memop d a s t) }
  | "get"(dist as d)(align as a)"."(mfxx as t) { GETMEMORY (memop d a ' ' t) }
  | "set"(dist as d)(align as a)"."(mfxx as t) { SETMEMORY (memop d a ' ' t) }

  | "const."(nxx as t) { CONST (value_type t) }

  | "neg."(ixx as t) { UNARY (intop t I32.Neg I64.Neg) }
  | "abs."(ixx as t) { UNARY (intop t I32.Abs I64.Abs) }
  | "not."(ixx as t) { UNARY (intop t I32.Not I64.Not) }
  | "clz."(ixx as t) { UNARY (intop t I32.Clz I64.Clz) }
  | "ctz."(ixx as t) { UNARY (intop t I32.Ctz I64.Ctz) }
  | "neg."(fxx as t) { UNARY (floatop t F32.Neg F64.Neg) }
  | "abs."(fxx as t) { UNARY (floatop t F32.Abs F64.Abs) }
  | "ceil."(fxx as t) { UNARY (floatop t F32.Ceil F64.Ceil) }
  | "floor."(fxx as t) { UNARY (floatop t F32.Floor F64.Floor) }
  | "trunc."(fxx as t) { UNARY (floatop t F32.Trunc F64.Trunc) }
  | "round."(fxx as t) { UNARY (floatop t F32.Round F64.Round) }

  | "add."(ixx as t) { BINARY (intop t I32.Add I64.Add) }
  | "sub."(ixx as t) { BINARY (intop t I32.Sub I64.Sub) }
  | "mul."(ixx as t) { BINARY (intop t I32.Mul I64.Mul) }
  | "divs."(ixx as t) { BINARY (intop t I32.DivS I64.DivS) }
  | "divu."(ixx as t) { BINARY (intop t I32.DivU I64.DivU) }
  | "mods."(ixx as t) { BINARY (intop t I32.ModS I64.ModS) }
  | "modu."(ixx as t) { BINARY (intop t I32.ModU I64.ModU) }
  | "and."(ixx as t) { BINARY (intop t I32.And I64.And) }
  | "or."(ixx as t) { BINARY (intop t I32.Or I64.Or) }
  | "xor."(ixx as t) { BINARY (intop t I32.Xor I64.Xor) }
  | "shl."(ixx as t) { BINARY (intop t I32.Shl I64.Shl) }
  | "shr."(ixx as t) { BINARY (intop t I32.Shr I64.Shr) }
  | "sar."(ixx as t) { BINARY (intop t I32.Sar I64.Sar) }
  | "add."(fxx as t) { BINARY (floatop t F32.Add F64.Add) }
  | "sub."(fxx as t) { BINARY (floatop t F32.Sub F64.Sub) }
  | "mul."(fxx as t) { BINARY (floatop t F32.Mul F64.Mul) }
  | "div."(fxx as t) { BINARY (floatop t F32.Div F64.Div) }
  | "mod."(fxx as t) { BINARY (floatop t F32.Mod F64.Mod) }
  | "copysign."(fxx as t) { BINARY (floatop t F32.CopySign F64.CopySign) }

  | "eq."(ixx as t) { COMPARE (intop t I32.Eq I64.Eq) }
  | "neq."(ixx as t) { COMPARE (intop t I32.Neq I64.Neq) }
  | "lts."(ixx as t) { COMPARE (intop t I32.LtS I64.LtS) }
  | "ltu."(ixx as t) { COMPARE (intop t I32.LtU I64.LtU) }
  | "les."(ixx as t) { COMPARE (intop t I32.LeS I64.LeS) }
  | "leu."(ixx as t) { COMPARE (intop t I32.LeU I64.LeU) }
  | "gts."(ixx as t) { COMPARE (intop t I32.GtS I64.GtS) }
  | "gtu."(ixx as t) { COMPARE (intop t I32.GtU I64.GtU) }
  | "ges."(ixx as t) { COMPARE (intop t I32.GeS I64.GeS) }
  | "geu."(ixx as t) { COMPARE (intop t I32.GeU I64.GtU) }
  | "eq."(fxx as t) { COMPARE (floatop t F32.Eq F64.Eq) }
  | "neq."(fxx as t) { COMPARE (floatop t F32.Neq F64.Neq) }
  | "lt."(fxx as t) { COMPARE (floatop t F32.Lt F64.Lt) }
  | "le."(fxx as t) { COMPARE (floatop t F32.Le F64.Le) }
  | "gt."(fxx as t) { COMPARE (floatop t F32.Gt F64.Gt) }
  | "ge."(fxx as t) { COMPARE (floatop t F32.Ge F64.Ge) }

  | "converts."(ixx as t)".i32" { CONVERT (intop t I32.ToInt32S I64.ToInt32S) }
  | "convertu."(ixx as t)".i32" { CONVERT (intop t I32.ToInt32U I64.ToInt32U) }
  | "converts."(ixx as t)".i64" { CONVERT (intop t I32.ToInt64S I64.ToInt64S) }
  | "convertu."(ixx as t)".i64" { CONVERT (intop t I32.ToInt64U I64.ToInt64U) }
  | "converts."(ixx as t)".f32"
    { CONVERT (intop t I32.ToFloat32S I64.ToFloat32S) }
  | "convertu."(ixx as t)".f32"
    { CONVERT (intop t I32.ToFloat32U I64.ToFloat32U) }
  | "converts."(ixx as t)".f64"
    { CONVERT (intop t I32.ToFloat64S I64.ToFloat64S) }
  | "convertu."(ixx as t)".f64"
    { CONVERT (intop t I32.ToFloat64U I64.ToFloat64U) }
  | "converts."(fxx as t)".i32"
    { CONVERT (floatop t F32.ToInt32S F64.ToInt32S) }
  | "convertu."(fxx as t)".i32"
    { CONVERT (floatop t F32.ToInt32U F64.ToInt32U) }
  | "converts."(fxx as t)".i64"
    { CONVERT (floatop t F32.ToInt64S F64.ToInt64S) }
  | "convertu."(fxx as t)".i64"
    { CONVERT (floatop t F32.ToInt64U F64.ToInt64U) }
  | "convert."(fxx as t)".f32"
    { CONVERT (floatop t F32.ToFloat32 F64.ToFloat32) }
  | "convert."(fxx as t)".f64"
    { CONVERT (floatop t F32.ToFloat64 F64.ToFloat64) }

  | "cast.i32.f32" { CONVERT (Int32 I32.ToFloatCast) }
  | "cast.i64.f64" { CONVERT (Int64 I64.ToFloatCast) }
  | "cast.f32.i32" { CONVERT (Float32 F32.ToIntCast) }
  | "cast.f64.i64" { CONVERT (Float64 F64.ToIntCast) }

  | "func" { FUNC }
  | "param" { PARAM }
  | "result" { RESULT }
  | "local" { LOCAL }
  | "module" { MODULE }
  | "global" { GLOBAL }
  | "import" { IMPORT }
  | "export" { EXPORT }
  | "table" { TABLE }

  | "memory" { MEMORY }
  | "invoke" { INVOKE }

  | ";;"[^'\n']*eof { EOF }
  | ";;"[^'\n']*'\n' { Lexing.new_line lexbuf; token lexbuf }
  | "(;" { comment (Lexing.lexeme_start_p lexbuf) lexbuf; token lexbuf }
  | space { token lexbuf }
  | '\n' { Lexing.new_line lexbuf; token lexbuf }
  | eof { EOF }
  | _ { error lexbuf "unknown opcode" }

and comment start = parse
  | ";)" { () }
  | "(;" { comment (Lexing.lexeme_start_p lexbuf) lexbuf; comment start lexbuf }
  | '\n' { Lexing.new_line lexbuf; comment start lexbuf }
  | eof { error_nest start lexbuf "unclosed comment" }
  | _ { comment start lexbuf }
