from __future__ import annotations

from typing import Dict, List, Optional, Set, Tuple

from .ir_types import (
    IRInstruction, IRBinOp, IRUnOp, IRCopy,
    IRLoad, IRStore, IRLabel, IRGoto,
    IRIfTrue, IRIfFalse, IRParam, IRCall, IRReturn,
    BinOp, UnOp, _is_literal,
)
from .ir_program import IRProgram, IRFunction
from .cfg import CFG
from .liveness import analyze_liveness, instr_liveness


# ---------------------------------------------------------------------------

WORD = 4  # bytes per word

# Scratch registers for computation
_T0, _T1, _T2 = "t0", "t1", "t2"
# Extra scratch for loading absolute addresses (does not touch t0/t1/t2)
_T3 = "t3"

# Argument / return registers
_ARG_REGS = ["a0", "a1", "a2", "a3", "a4", "a5"]

# Callee-saved registers available for IR-temp allocation
_SREG_POOL = [
    "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9",
    "s10", "s11", "s12", "s13",
]

# Arithmetic/logic IR operators -> GAEM R-type mnemonic
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

# Comparison IR operators -> GAEM conditional branch mnemonic
_CMP_BRANCH: Dict[BinOp, str] = {
    BinOp.EQ:  "beq",
    BinOp.NEQ: "bne",
    BinOp.GT:  "bgt",
    BinOp.LT:  "blt",
    BinOp.GE:  "bge",
    BinOp.LE:  "ble",
}


# ---------------------------------------------------------------------------

class IRCodeGenerator:
    """Translate a full IRProgram to GAEM assembly text."""

    def __init__(self, symbol_table, label_table, fixup_table):
        self.symbol_table = symbol_table
        self.label_table  = label_table
        self.fixup_table  = fixup_table

        # ASM text lines and instruction counter (for label_table)
        self._lines: List[str] = []
        self._instr_count: int = 0

        # Global counter for auxiliary labels (CMP_TRUE_n, NOT_END_n, etc.)
        self._label_counter: int = 0

        # Per-function state (reset in _gen_function)
        self._temp_slots: Dict[str, int] = {}   # var -> frame offset
        self._temp_regs:  Dict[str, str] = {}   # var -> s-register (allocated temps)
        self._frame_size: int = 0
        self._return_label: str = ""
        self._func_name: str = ""
        self._pending_params: List[str] = []    # params accumulated before call

    # -----------------------------------------------------------------------

    def generate(self, ir_program: IRProgram) -> str:
        """Generate full ASM text for ir_program; returns ready-to-assemble string."""
        # Header: ENTRY + sp init + call to main (only if main exists)
        self._emit_label("ENTRY")
        self._emit("luhw sp, 0x0003")
        self._emit("llhw sp, 0xFFFC")
        _, main_sym = self.symbol_table.lookup("main")
        if main_sym is not None:
            self._emit_jump(f"jal ra, FUNC_main", "FUNC_main", "JAL")

        # Infinite loop at program end
        self._emit_label("PROGRAM_END")
        self._emit_jump("j PROGRAM_END", "PROGRAM_END", "J")

        for ir_func in ir_program.functions:
            self._gen_function(ir_func)

        return "\n".join(self._lines)

    # -----------------------------------------------------------------------

    def _gen_function(self, ir_func: IRFunction) -> None:
        """Generate prologue + body + epilogue for one IR function."""
        self._func_name    = ir_func.name
        self._return_label = f"FUNC_{ir_func.name}_RETURN"
        self._pending_params = []

        # Fetch function symbol before entering scope
        _, func_sym = self.symbol_table.lookup(ir_func.name)
        base_frame  = func_sym.get("frame_size", WORD) if func_sym else WORD

        self.symbol_table.enter_scope(ir_func.name, reset_local=False)

        # Collect all variable names referenced in the body
        all_vars: set = set()
        for instr in ir_func.body:
            all_vars.update(instr.defs())
            all_vars.update(instr.uses())

        # Assign stack slots to IR temporals not in the symbol table
        self._temp_slots = {}
        self._frame_size = base_frame
        for var in sorted(all_vars):           # sorted for determinism
            if _is_literal(var):
                continue
            if var.startswith("@"):            # global address ref - no slot needed
                continue
            _, sym = self.symbol_table.lookup(var)
            if sym is None and var not in self._temp_slots:
                self._temp_slots[var] = self._frame_size
                self._frame_size += WORD

        # S-register allocation: assign s0-s13 to IR temps not live at any call site.
        # Temps in _temp_regs keep their stack slot (for a correct frame) but
        # _load_val/_store_val will use the s-register instead of the stack.
        self._temp_regs = {}
        self._alloc_sregs(ir_func)

        # Build a map: instruction index -> (block_id, preds, succs)
        # Used to emit block-boundary comments in the ASM output.
        cfg_for_comments = CFG.build_from_function(ir_func)
        _block_start: Dict[int, tuple] = {}
        _flat = ir_func.body
        for block in cfg_for_comments.blocks:
            # Find the index of the first instruction of this block in the flat body
            if block.instructions:
                first_instr = block.instructions[0]
                for idx, instr in enumerate(_flat):
                    if instr is first_instr:
                        pred_ids = [f"B{p.id}" for p in block.predecessors]
                        succ_ids = [f"B{s.id}" for s in block.successors]
                        _block_start[idx] = (block.id, pred_ids, succ_ids)
                        break

        # First IR instruction is often IRLabel("FUNC_name")
        body = ir_func.body
        start_idx = 0
        if (body and isinstance(body[0], IRLabel)
                and body[0].name == f"FUNC_{ir_func.name}"):
            self._emit_label(body[0].name)
            start_idx = 1
        else:
            self._emit_label(f"FUNC_{ir_func.name}")

        # Prologue
        self._emit(f"addi sp, sp, -{self._frame_size}")
        self._emit(f"sw ra, 0(sp)")

        # Save incoming arguments to their frame slots
        params = func_sym.get("parameters", []) if func_sym else []
        for idx, param in enumerate(params):
            if idx >= len(_ARG_REGS):
                break
            _, psym = self.symbol_table.lookup(param["name"])
            if psym and psym.get("is_local"):
                self._emit(f"sw {_ARG_REGS[idx]}, {psym['address']}(sp)")

        # Body - emit block-boundary comments whenever a new block starts
        _SEP = "=" * 44
        for idx, instr in enumerate(body[start_idx:], start=start_idx):
            if idx in _block_start:
                bid, preds, succs = _block_start[idx]
                self._lines.append(f"    # {_SEP}")
                self._lines.append(f"    # BLOCK {bid}   preds={preds}  succs={succs}")
                self._lines.append(f"    # {_SEP}")
            self._gen_instr(instr)

        # Epilogue
        self._emit_label(self._return_label)
        self._emit(f"lw ra, 0(sp)")
        self._emit(f"addi sp, sp, {self._frame_size}")
        self._emit("jr ra")

        self.symbol_table.exit_scope()

    # -----------------------------------------------------------------------

    def _alloc_sregs(self, ir_func: IRFunction) -> None:
        """Linear-scan s-register allocation for IR temporaries.

        Temps that are live at any IRCall site cannot be safely allocated to
        caller-clobberable registers, so they stay on the stack. All others are
        assigned s0-s13 in live-range order to avoid load-use stalls.
        """
        all_temp_vars: Set[str] = set(self._temp_slots.keys())
        if not all_temp_vars:
            return

        cfg = CFG.build_from_function(ir_func)
        lr  = analyze_liveness(cfg)

        # Temps live at any call site must stay on stack
        call_live: Set[str] = set()
        for block in cfg.blocks:
            il = instr_liveness(block, lr.live_out(block))
            for i, instr in enumerate(block.instructions):
                if isinstance(instr, IRCall):
                    call_live |= il[i].live_before & all_temp_vars

        eligible: Set[str] = all_temp_vars - call_live
        if not eligible:
            return

        # Map each IRParam index to the index of its following IRCall.
        # Param values are deferred and loaded at call time, so they are
        # effectively live until the call, not just until the IRParam.
        param_call_end: Dict[int, int] = {}
        for idx, instr in enumerate(ir_func.body):
            if isinstance(instr, IRParam):
                for j in range(idx + 1, len(ir_func.body)):
                    if isinstance(ir_func.body[j], IRCall):
                        param_call_end[idx] = j
                        break

        # Build live ranges over the flat body (instruction index)
        live_ranges: Dict[str, Tuple[int, int]] = {}
        for idx, instr in enumerate(ir_func.body):
            effective_idx = param_call_end.get(idx, idx) if isinstance(instr, IRParam) else idx
            for var in instr.defs() | instr.uses():
                if var in eligible:
                    lo, hi = live_ranges.get(var, (idx, idx))
                    live_ranges[var] = (min(lo, idx), max(hi, effective_idx))

        # Linear scan
        active: List[Tuple[int, str, str]] = []  # (end, var, reg)
        for var in sorted(eligible, key=lambda v: live_ranges.get(v, (0, 0))[0]):
            if var not in live_ranges:
                continue
            start, end = live_ranges[var]
            active = [(e, v, r) for (e, v, r) in active if e >= start]
            used = {r for (_, _, r) in active}
            free = [r for r in _SREG_POOL if r not in used]
            if free:
                s = free[0]
                self._temp_regs[var] = s
                active.append((end, var, s))

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

    def _dreg(self, var: str) -> str:
        """Return the s-register allocated to var, or _T2 as default scratch."""
        return self._temp_regs.get(var, _T2)

    def _creg(self, var: str) -> str:
        """Return the register holding var for a condition test (branch operand)."""
        if var in self._temp_regs:
            return self._temp_regs[var]
        self._load_val(_T0, var)
        return _T0

    def _load_binop_operands(self, left: str, right: str) -> tuple[str, str]:
        """Load binop operands into the most efficient registers.

        If an operand is already in a s-register, use it directly to avoid a
        redundant register-to-register move. Returns (lreg, rreg).
        """
        lreg = self._temp_regs.get(left)
        rreg = self._temp_regs.get(right)

        if lreg and rreg:
            # Both in s-regs: no loads needed
            pass
        elif lreg:
            # left is in s-reg; load right into _T1
            self._load_val(_T1, right)
            rreg = _T1
        elif rreg:
            # right is in s-reg; load left into _T0
            self._load_val(_T0, left)
            lreg = _T0
        else:
            # Neither in s-reg: load both normally
            self._load_val(_T0, left)
            self._load_val(_T1, right)
            lreg, rreg = _T0, _T1

        return lreg, rreg

    # -----------------------------------------------------------------------

    def _gen_binop(self, instr: IRBinOp) -> None:
        self._comment(str(instr))
        lreg, rreg = self._load_binop_operands(instr.left, instr.right)
        dr = self._dreg(instr.dest)

        if instr.op in _RTYPE:
            self._emit(f"{_RTYPE[instr.op]} {dr}, {lreg}, {rreg}")

        elif instr.op in _CMP_BRANCH:
            # Branch to TRUE_n; false path emits 0, then jumps to END_n; TRUE_n emits 1
            branch  = _CMP_BRANCH[instr.op]
            lbl_t   = self._new_label("CMP_T")
            lbl_end = self._new_label("CMP_E")
            self._emit_branch(f"{branch} {lreg}, {rreg}, {lbl_t}", lbl_t)
            self._emit(f"addi {dr}, zero, 0")
            self._emit_jump(f"j {lbl_end}", lbl_end, "J")
            self._emit_label(lbl_t)
            self._emit(f"addi {dr}, zero, 1")
            self._emit_label(lbl_end)

        self._store_val(dr, instr.dest)

    # -----------------------------------------------------------------------

    def _gen_unop(self, instr: IRUnOp) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.operand)
        dr = self._dreg(instr.dest)

        if instr.op == UnOp.NEG:
            self._emit(f"sub {dr}, zero, {_T0}")
            self._store_val(dr, instr.dest)

        elif instr.op == UnOp.NOT:
            # Logical NOT: 1 if operand == 0, else 0
            lbl_t   = self._new_label("NOT_T")
            lbl_end = self._new_label("NOT_E")
            self._emit_branch(f"beq {_T0}, zero, {lbl_t}", lbl_t)
            self._emit(f"addi {dr}, zero, 0")
            self._emit_jump(f"j {lbl_end}", lbl_end, "J")
            self._emit_label(lbl_t)
            self._emit(f"addi {dr}, zero, 1")
            self._emit_label(lbl_end)
            self._store_val(dr, instr.dest)

    # -----------------------------------------------------------------------

    def _gen_copy(self, instr: IRCopy) -> None:
        self._comment(str(instr))
        dr = self._dreg(instr.dest)
        self._load_val(dr, instr.src)
        self._store_val(dr, instr.dest)

    # -----------------------------------------------------------------------

    def _gen_ir_load(self, instr: IRLoad) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.base)          # t0 = pointer value
        dr = self._dreg(instr.dest)
        if instr.offset != 0:
            self._emit(f"addi {_T1}, {_T0}, {instr.offset}")
            self._emit(f"lw {dr}, 0({_T1})")
        else:
            self._emit(f"lw {dr}, 0({_T0})")
        self._store_val(dr, instr.dest)

    # -----------------------------------------------------------------------

    def _gen_ir_store(self, instr: IRStore) -> None:
        self._comment(str(instr))
        self._load_val(_T0, instr.base)          # t0 = pointer
        self._load_val(_T1, instr.src)           # t1 = value to write
        if instr.offset != 0:
            self._emit(f"addi {_T2}, {_T0}, {instr.offset}")
            self._emit(f"sw {_T1}, 0({_T2})")
        else:
            self._emit(f"sw {_T1}, 0({_T0})")

    # -----------------------------------------------------------------------

    def _gen_ir_label(self, instr: IRLabel) -> None:
        self._emit_label(instr.name)

    # -----------------------------------------------------------------------

    def _gen_goto(self, instr: IRGoto) -> None:
        self._comment(str(instr))
        self._emit_jump(f"j {instr.target}", instr.target, "J")

    # -----------------------------------------------------------------------

    def _gen_iftrue(self, instr: IRIfTrue) -> None:
        self._comment(str(instr))
        cr = self._creg(instr.cond)
        self._emit_branch(f"bne {cr}, zero, {instr.target}", instr.target)

    # -----------------------------------------------------------------------

    def _gen_iffalse(self, instr: IRIfFalse) -> None:
        self._comment(str(instr))
        cr = self._creg(instr.cond)
        self._emit_branch(f"beq {cr}, zero, {instr.target}", instr.target)

    # -----------------------------------------------------------------------

    def _gen_param(self, instr: IRParam) -> None:
        self._pending_params.append(instr.value)

    # -----------------------------------------------------------------------

    def _gen_call(self, instr: IRCall) -> None:
        self._comment(str(instr))
        # Load accumulated params into a0..a5
        for i, val in enumerate(self._pending_params):
            if i >= len(_ARG_REGS):
                break
            self._load_val(_ARG_REGS[i], val)
        self._pending_params.clear()

        func_label = f"FUNC_{instr.func}"
        self._emit_jump(f"jal ra, {func_label}", func_label, "JAL")

        # Store return value if there is a destination
        if instr.dest:
            self._store_val("a0", instr.dest)

    # -----------------------------------------------------------------------

    def _gen_return(self, instr: IRReturn) -> None:
        self._comment(str(instr))
        if instr.value is not None:
            self._load_val("a0", instr.value)
        self._emit_jump(f"j {self._return_label}", self._return_label, "J")

    # -----------------------------------------------------------------------

    def _load_val(self, reg: str, var: str) -> None:
        """Load the value of var (or a literal) into reg."""
        if _is_literal(var):
            v = int(var, 0)
            if -2048 <= v <= 2047:
                self._emit(f"addi {reg}, zero, {v}")
            else:
                self._emit(f"li {reg}, {v}")
            return

        # @name means "absolute address of global symbol name"
        if var.startswith("@"):
            actual_name = var[1:]
            _, sym = self.symbol_table.lookup(actual_name)
            if sym is not None:
                self._emit(f"li {reg}, {sym['address']}")
                return
            raise RuntimeError(
                f"IRCodeGenerator: global '{var}' not found in '{self._func_name}'"
            )

        _, sym = self.symbol_table.lookup(var)
        if sym is not None:
            if sym.get("is_local"):
                if sym.get("kind") == "array":
                    # Local array: yield the frame address, not the value stored there
                    self._emit(f"addi {reg}, sp, {sym['address']}")
                else:
                    self._emit(f"lw {reg}, {sym['address']}(sp)")
            else:
                # Global scalar: load absolute address into t3, then dereference
                self._emit(f"li {_T3}, {sym['address']}")
                self._emit(f"lw {reg}, 0({_T3})")
            return

        if var in self._temp_regs:
            s = self._temp_regs[var]
            if s != reg:
                self._emit(f"add {reg}, {s}, zero")
            return

        if var in self._temp_slots:
            self._emit(f"lw {reg}, {self._temp_slots[var]}(sp)")
            return

        raise RuntimeError(
            f"IRCodeGenerator: variable '{var}' has no slot in '{self._func_name}'"
        )

    def _store_val(self, reg: str, var: str) -> None:
        """Store reg into the stack slot of var."""
        _, sym = self.symbol_table.lookup(var)
        if sym is not None:
            if sym.get("is_local"):
                self._emit(f"sw {reg}, {sym['address']}(sp)")
            else:
                self._emit(f"li {_T3}, {sym['address']}")
                self._emit(f"sw {reg}, 0({_T3})")
            return

        if var in self._temp_regs:
            s = self._temp_regs[var]
            if s != reg:
                self._emit(f"add {s}, {reg}, zero")
            return

        if var in self._temp_slots:
            self._emit(f"sw {reg}, {self._temp_slots[var]}(sp)")
            return

        raise RuntimeError(
            f"IRCodeGenerator: variable '{var}' has no slot (store) in '{self._func_name}'"
        )

    # -----------------------------------------------------------------------

    def _emit(self, instr: str) -> None:
        """Emit one instruction (4 bytes in the final binary)."""
        self._instr_count += 1
        self._lines.append(f"    {instr}")

    def _comment(self, text: str) -> None:
        """Emit a comment line (no bytes generated)."""
        self._lines.append(f"    # {text}")

    def _emit_label(self, name: str) -> None:
        """Emit a label and register it in the label table."""
        pc = (self._instr_count) * WORD
        try:
            self.label_table.define_label(name, pc)
        except Exception:
            pass   # duplicate label: encoder resolves from text
        self._lines.append(f"{name}:")

    def _emit_jump(self, instr: str, label: str, jump_type: str) -> None:
        """Emit an unconditional jump or jal; register in fixup table."""
        self.fixup_table.add_fixup(self._instr_count, label, jump_type)
        self._emit(instr)

    def _emit_branch(self, instr: str, label: str) -> None:
        """Emit a conditional branch; register in fixup table."""
        self.fixup_table.add_fixup(self._instr_count, label, "B")
        self._emit(instr)

    def _new_label(self, prefix: str) -> str:
        """Generate a unique auxiliary label."""
        name = f"_{prefix}_{self._label_counter}"
        self._label_counter += 1
        return name
