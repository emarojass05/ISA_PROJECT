"""
ir_codegen.py - Generacion de codigo assembly desde IR optimizada.

Traduce un IRProgram (posiblemente optimizado por O1/O2) a texto assembly
compatible con el encoder.py de la ISA GAEM.

Estrategia de generacion
------------------------
Modelo load-compute-store: cada instruccion IR genera una secuencia
  1. Cargar operandos a registros scratch (t0, t1).
  2. Ejecutar la operacion.
  3. Almacenar el resultado en el slot de stack del destino.

Asignacion de variables
-----------------------
  - Variables declaradas (params, locals): usan el offset de frame
    calculado por SemanticTableBuilder y guardado en symbol_table.
  - Temporales IR (_t0, _rn0_x, etc.): reciben slots adicionales al
    final del frame, asignados por IRCodeGenerator al analizar el cuerpo.

Registros reservados
--------------------
  t0, t1, t2  scratch para computo
  t3          scratch para cargar direcciones absolutas (globals)
  a0..a5      argumentos de llamada / valor de retorno (a0)
  ra          direccion de retorno (gestionada por prologue/epilogue)
  sp          puntero de stack

Estructura del ASM generado
----------------------------
  ENTRY:
      luhw sp, 0x0003          ; inicializar sp en top of data memory
      llhw sp, 0xFFFC
      jal ra, FUNC_main        ; invocar main
  PROGRAM_END:
      j PROGRAM_END            ; loop infinito

  FUNC_foo:
      addi sp, sp, -<frame>    ; prologue
      sw ra, 0(sp)
      sw a0, <p0_off>(sp)      ; guardar params
      ...
      <cuerpo traducido>
  FUNC_foo_RETURN:
      lw ra, 0(sp)             ; epilogue
      addi sp, sp, <frame>
      jr ra

  FUNC_main:
      ...

Interfaz publica
----------------
    IRCodeGenerator
    IRCodeGenerator.generate(ir_program) -> str    (texto ASM)
"""

from __future__ import annotations

from typing import Dict, List, Optional

from .ir_types import (
    IRInstruction, IRBinOp, IRUnOp, IRCopy,
    IRLoad, IRStore, IRLabel, IRGoto,
    IRIfTrue, IRIfFalse, IRParam, IRCall, IRReturn,
    BinOp, UnOp, _is_literal,
)
from .ir_program import IRProgram, IRFunction


# ---------------------------------------------------------------------------
# Constantes ISA GAEM
# ---------------------------------------------------------------------------

WORD = 4  # bytes por palabra

# Registros scratch para computo
_T0, _T1, _T2 = "t0", "t1", "t2"
# Scratch extra para cargar direcciones absolutas (no toca t0/t1/t2)
_T3 = "t3"

# Registros de argumento / retorno
_ARG_REGS = ["a0", "a1", "a2", "a3", "a4", "a5"]

# Mapeo de operadores aritmeticos/logicos IR -> mnemonico R-type GAEM
_RTYPE: Dict[BinOp, str] = {
    BinOp.ADD: "add",
    BinOp.SUB: "sub",
    BinOp.MUL: "mul",
    BinOp.DIV: "div",
    BinOp.MOD: "rem",
    BinOp.AND: "and",
    BinOp.OR:  "or",
    BinOp.XOR: "xor",
    BinOp.SHL: "sll",
    BinOp.SHR: "srl",
}

# Comparaciones: operador IR -> instruccion de salto condicional GAEM
_CMP_BRANCH: Dict[BinOp, str] = {
    BinOp.EQ:  "beq",
    BinOp.NEQ: "bne",
    BinOp.GT:  "bgt",
    BinOp.LT:  "blt",
    BinOp.GE:  "bge",
    BinOp.LE:  "ble",
}


# ---------------------------------------------------------------------------
# Generador principal
# ---------------------------------------------------------------------------

class IRCodeGenerator:
    """
    Traduce un IRProgram completo a texto assembly de la ISA GAEM.

    Uso:
        gen = IRCodeGenerator(symbol_table, label_table, fixup_table)
        asm_text = gen.generate(ir_program)
        hex_code = encoder.assemble(asm_text)
    """

    def __init__(self, symbol_table, label_table, fixup_table):
        self.symbol_table = symbol_table
        self.label_table  = label_table
        self.fixup_table  = fixup_table

        # Lineas de texto ASM y contador de instrucciones (para el label_table)
        self._lines: List[str] = []
        self._instr_count: int = 0

        # Contador global de etiquetas auxiliares (CMP_TRUE_n, NOT_END_n, etc.)
        self._label_counter: int = 0

        # ---- Estado por funcion (se resetea en cada _gen_function) ----
        self._temp_slots: Dict[str, int] = {}   # var -> offset en frame
        self._frame_size: int = 0
        self._return_label: str = ""
        self._func_name: str = ""
        self._pending_params: List[str] = []    # params acumulados antes del call

    # -----------------------------------------------------------------------
    # Interfaz publica
    # -----------------------------------------------------------------------

    def generate(self, ir_program: IRProgram) -> str:
        """
        Genera el texto ASM completo para ir_program.
        Retorna un string listo para pasar a encoder.assemble().
        """
        # Cabecera: ENTRY + inicializacion de sp + llamada a main
        self._emit_label("ENTRY")
        self._emit("luhw sp, 0x0003")
        self._emit("llhw sp, 0xFFFC")
        self._emit_jump(f"jal ra, FUNC_main", "FUNC_main", "JAL")

        # Loop infinito al final del programa
        self._emit_label("PROGRAM_END")
        self._emit_jump("j PROGRAM_END", "PROGRAM_END", "J")

        # Codigo de cada funcion
        for ir_func in ir_program.functions:
            self._gen_function(ir_func)

        return "\n".join(self._lines)

    # -----------------------------------------------------------------------
    # Generacion de una funcion
    # -----------------------------------------------------------------------

    def _gen_function(self, ir_func: IRFunction) -> None:
        """Genera prologue + body + epilogue para una funcion IR."""
        self._func_name    = ir_func.name
        self._return_label = f"FUNC_{ir_func.name}_RETURN"
        self._pending_params = []

        # Obtener simbolo de la funcion (scope global) antes de enter_scope
        _, func_sym = self.symbol_table.lookup(ir_func.name)
        base_frame  = func_sym.get("frame_size", WORD) if func_sym else WORD

        # Entrar al scope para poder resolver variables locales
        self.symbol_table.enter_scope(ir_func.name, reset_local=False)

        # Recolectar todos los nombres de variables del cuerpo
        all_vars: set = set()
        for instr in ir_func.body:
            all_vars.update(instr.defs())
            all_vars.update(instr.uses())

        # Asignar slots de stack a los temporales IR que no esten en symbol_table
        self._temp_slots = {}
        self._frame_size = base_frame
        for var in sorted(all_vars):           # sorted => determinismo
            if _is_literal(var):
                continue
            _, sym = self.symbol_table.lookup(var)
            if sym is None and var not in self._temp_slots:
                self._temp_slots[var] = self._frame_size
                self._frame_size += WORD

        # El primer IR de la funcion suele ser IRLabel("FUNC_name")
        body = ir_func.body
        start_idx = 0
        if (body and isinstance(body[0], IRLabel)
                and body[0].name == f"FUNC_{ir_func.name}"):
            self._emit_label(body[0].name)
            start_idx = 1
        else:
            self._emit_label(f"FUNC_{ir_func.name}")

        # --- Prologue ---
        self._emit(f"addi sp, sp, -{self._frame_size}")
        self._emit(f"sw ra, 0(sp)")

        # Guardar argumentos entrantes en sus slots de frame
        params = func_sym.get("parameters", []) if func_sym else []
        for idx, param in enumerate(params):
            if idx >= len(_ARG_REGS):
                break   # mas de 6 args: ignorar por ahora
            _, psym = self.symbol_table.lookup(param["name"])
            if psym and psym.get("is_local"):
                self._emit(f"sw {_ARG_REGS[idx]}, {psym['address']}(sp)")

        # --- Cuerpo ---
        for instr in body[start_idx:]:
            self._gen_instr(instr)

        # --- Epilogue ---
        self._emit_label(self._return_label)
        self._emit(f"lw ra, 0(sp)")
        self._emit(f"addi sp, sp, {self._frame_size}")
        self._emit("jr ra")

        self.symbol_table.exit_scope()

    # -----------------------------------------------------------------------
    # Despacho de instrucciones IR
    # -----------------------------------------------------------------------

    def _gen_instr(self, instr: IRInstruction) -> None:
        if   isinstance(instr, IRBinOp):   self._gen_binop(instr)
        elif isinstance(instr, IRUnOp):    self._gen_unop(instr)
        elif isinstance(instr, IRCopy):    self._gen_copy(instr)
        elif isinstance(instr, IRLoad):    self._gen_ir_load(instr)
        elif isinstance(instr, IRStore):   self._gen_ir_store(instr)
        elif isinstance(instr, IRLabel):   self._gen_ir_label(instr)
        elif isinstance(instr, IRGoto):    self._gen_goto(instr)
        elif isinstance(instr, IRIfTrue):  self._gen_iftrue(instr)
        elif isinstance(instr, IRIfFalse): self._gen_iffalse(instr)
        elif isinstance(instr, IRParam):   self._gen_param(instr)
        elif isinstance(instr, IRCall):    self._gen_call(instr)
        elif isinstance(instr, IRReturn):  self._gen_return(instr)

    # -----------------------------------------------------------------------
    # Operacion binaria
    # -----------------------------------------------------------------------

    def _gen_binop(self, instr: IRBinOp) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.left)
        self._load_val(_T1, instr.right)

        if instr.op in _RTYPE:
            self._emit(f"{_RTYPE[instr.op]} {_T2}, {_T0}, {_T1}")

        elif instr.op in _CMP_BRANCH:
            # Secuencia: branch a TRUE_n, False path = 0, j END_n, TRUE_n: 1
            branch  = _CMP_BRANCH[instr.op]
            lbl_t   = self._new_label("CMP_T")
            lbl_end = self._new_label("CMP_E")
            self._emit_branch(f"{branch} {_T0}, {_T1}, {lbl_t}", lbl_t)
            self._emit(f"addi {_T2}, zero, 0")
            self._emit_jump(f"j {lbl_end}", lbl_end, "J")
            self._emit_label(lbl_t)
            self._emit(f"addi {_T2}, zero, 1")
            self._emit_label(lbl_end)

        self._store_val(_T2, instr.dest)

    # -----------------------------------------------------------------------
    # Operacion unaria
    # -----------------------------------------------------------------------

    def _gen_unop(self, instr: IRUnOp) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.operand)

        if instr.op == UnOp.NEG:
            # sub t1, zero, t0  ->  t1 = 0 - t0
            self._emit(f"sub {_T1}, zero, {_T0}")
            self._store_val(_T1, instr.dest)

        elif instr.op == UnOp.NOT:
            # NOT logico: resultado 1 si operando == 0, 0 si != 0
            lbl_t   = self._new_label("NOT_T")
            lbl_end = self._new_label("NOT_E")
            self._emit_branch(f"beq {_T0}, zero, {lbl_t}", lbl_t)
            self._emit(f"addi {_T1}, zero, 0")
            self._emit_jump(f"j {lbl_end}", lbl_end, "J")
            self._emit_label(lbl_t)
            self._emit(f"addi {_T1}, zero, 1")
            self._emit_label(lbl_end)
            self._store_val(_T1, instr.dest)

    # -----------------------------------------------------------------------
    # Copia simple
    # -----------------------------------------------------------------------

    def _gen_copy(self, instr: IRCopy) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.src)
        self._store_val(_T0, instr.dest)

    # -----------------------------------------------------------------------
    # Carga desde memoria  dest = mem[base + offset]
    # -----------------------------------------------------------------------

    def _gen_ir_load(self, instr: IRLoad) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.base)          # t0 = valor del puntero
        if instr.offset != 0:
            self._emit(f"addi {_T1}, {_T0}, {instr.offset}")
            self._emit(f"lw {_T2}, 0({_T1})")
        else:
            self._emit(f"lw {_T2}, 0({_T0})")
        self._store_val(_T2, instr.dest)

    # -----------------------------------------------------------------------
    # Escritura en memoria  mem[base + offset] = src
    # -----------------------------------------------------------------------

    def _gen_ir_store(self, instr: IRStore) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.base)          # t0 = puntero
        self._load_val(_T1, instr.src)           # t1 = valor a escribir
        if instr.offset != 0:
            self._emit(f"addi {_T2}, {_T0}, {instr.offset}")
            self._emit(f"sw {_T1}, 0({_T2})")
        else:
            self._emit(f"sw {_T1}, 0({_T0})")

    # -----------------------------------------------------------------------
    # Etiqueta IR (salto condicional, loop, etc.)
    # -----------------------------------------------------------------------

    def _gen_ir_label(self, instr: IRLabel) -> None:
        self._emit_label(instr.name)

    # -----------------------------------------------------------------------
    # Salto incondicional
    # -----------------------------------------------------------------------

    def _gen_goto(self, instr: IRGoto) -> None:
        self._comment(str(instr))
        self._emit_jump(f"j {instr.target}", instr.target, "J")

    # -----------------------------------------------------------------------
    # Salto condicional: verdadero
    # -----------------------------------------------------------------------

    def _gen_iftrue(self, instr: IRIfTrue) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.cond)
        self._emit_branch(f"bne {_T0}, zero, {instr.target}", instr.target)

    # -----------------------------------------------------------------------
    # Salto condicional: falso
    # -----------------------------------------------------------------------

    def _gen_iffalse(self, instr: IRIfFalse) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.cond)
        self._emit_branch(f"beq {_T0}, zero, {instr.target}", instr.target)

    # -----------------------------------------------------------------------
    # Parametro para llamada (se acumula, se emite en IRCall)
    # -----------------------------------------------------------------------

    def _gen_param(self, instr: IRParam) -> None:
        self._pending_params.append(instr.value)

    # -----------------------------------------------------------------------
    # Llamada a funcion
    # -----------------------------------------------------------------------

    def _gen_call(self, instr: IRCall) -> None:
        self._comment(str(instr))
        # Cargar params acumulados en a0..a5
        for i, val in enumerate(self._pending_params):
            if i >= len(_ARG_REGS):
                break
            self._load_val(_ARG_REGS[i], val)
        self._pending_params.clear()

        func_label = f"FUNC_{instr.func}"
        self._emit_jump(f"jal ra, {func_label}", func_label, "JAL")

        # Guardar valor de retorno si hay destino
        if instr.dest:
            self._store_val("a0", instr.dest)

    # -----------------------------------------------------------------------
    # Retorno de funcion
    # -----------------------------------------------------------------------

    def _gen_return(self, instr: IRReturn) -> None:
        self._comment(str(instr))
        if instr.value is not None:
            self._load_val("a0", instr.value)
        self._emit_jump(f"j {self._return_label}", self._return_label, "J")

    # -----------------------------------------------------------------------
    # Carga y almacenamiento de variables
    # -----------------------------------------------------------------------

    def _load_val(self, reg: str, var: str) -> None:
        """Carga el valor de var (o literal) en el registro reg."""
        if _is_literal(var):
            self._emit(f"li {reg}, {int(var, 0)}")
            return

        _, sym = self.symbol_table.lookup(var)
        if sym is not None:
            if sym.get("is_local"):
                self._emit(f"lw {reg}, {sym['address']}(sp)")
            else:
                # Variable global: cargar direccion absoluta en t3, luego lw
                self._emit(f"li {_T3}, {sym['address']}")
                self._emit(f"lw {reg}, 0({_T3})")
            return

        if var in self._temp_slots:
            self._emit(f"lw {reg}, {self._temp_slots[var]}(sp)")
            return

        raise RuntimeError(
            f"IRCodeGenerator: variable '{var}' sin slot en '{self._func_name}'"
        )

    def _store_val(self, reg: str, var: str) -> None:
        """Almacena el valor del registro reg en el slot de var."""
        _, sym = self.symbol_table.lookup(var)
        if sym is not None:
            if sym.get("is_local"):
                self._emit(f"sw {reg}, {sym['address']}(sp)")
            else:
                self._emit(f"li {_T3}, {sym['address']}")
                self._emit(f"sw {reg}, 0({_T3})")
            return

        if var in self._temp_slots:
            self._emit(f"sw {reg}, {self._temp_slots[var]}(sp)")
            return

        raise RuntimeError(
            f"IRCodeGenerator: variable '{var}' sin slot (store) en '{self._func_name}'"
        )

    # -----------------------------------------------------------------------
    # Helpers de emision
    # -----------------------------------------------------------------------

    def _emit(self, instr: str) -> None:
        """Emite una instruccion (4 bytes en el binario final)."""
        self._instr_count += 1
        self._lines.append(f"    {instr}")

    def _comment(self, text: str) -> None:
        """Emite un comentario (no genera bytes)."""
        self._lines.append(f"    # {text}")

    def _emit_label(self, name: str) -> None:
        """Emite una etiqueta y la registra en el label_table."""
        pc = (self._instr_count) * WORD
        try:
            self.label_table.define_label(name, pc)
        except Exception:
            pass   # etiqueta duplicada: el encoder resuelve del texto
        self._lines.append(f"{name}:")

    def _emit_jump(self, instr: str, label: str, jump_type: str) -> None:
        """Emite un salto incondicional o jal, y lo registra en fixup_table."""
        self.fixup_table.add_fixup(self._instr_count, label, jump_type)
        self._emit(instr)

    def _emit_branch(self, instr: str, label: str) -> None:
        """Emite un salto condicional y lo registra en fixup_table."""
        self.fixup_table.add_fixup(self._instr_count, label, "B")
        self._emit(instr)

    def _new_label(self, prefix: str) -> str:
        """Genera una etiqueta auxiliar unica."""
        name = f"_{prefix}_{self._label_counter}"
        self._label_counter += 1
        return name
