"""
tests/unit/test_cfg.py
======================
Unit tests for BasicBlock and CFG (feature/ir-basic-blocks-cfg).

IR is built by hand (no parser or IRGenerator) so tests are fast,
deterministic, and independent of the ANTLR grammar.

Cases covered
-------------
  BasicBlock
    - creation and initial attributes
    - append / first / last / is_empty
    - label() with and without IRLabel as first instruction
    - __str__ and __repr__
    - equality by identity (hash/eq)

  CFG - structural cases
    1. Empty function            -> 0 blocks
    2. Return only               -> 1 block, no successors
    3. Linear sequence           -> 1 block (no jumps)
    4. Simple if/else            -> 4 blocks, correct edges
    5. While loop                -> 3 blocks, back-edge
    6. If without else           -> 3 blocks
    7. Function call             -> does not split blocks
    8. Multiple returns          -> blocks without successor per return
    9. Unreachable labels        -> do not create extra blocks
   10. CFG.dot()                 -> valid DOT format (nodes and edges)
   11. get_block_by_label        -> searches by label name
   12. entry property            -> first block
"""

import pytest
from src.compiler.ir.ir_types import (
    IRBinOp, IRUnOp, IRCopy, IRLoad, IRStore,
    IRLabel, IRGoto, IRIfTrue, IRIfFalse,
    IRParam, IRCall, IRReturn,
    BinOp, UnOp,
)
from src.compiler.ir.ir_program import IRFunction
from src.compiler.ir.basic_block import BasicBlock
from src.compiler.ir.cfg import CFG


# ===========================================================================
# Helpers
# ===========================================================================

def make_func(name: str, *instrs) -> IRFunction:
    """Create an IRFunction with the given list of instructions."""
    func = IRFunction(name=name, params=[], return_type="int")
    for instr in instrs:
        func.emit(instr)
    return func


def cfg_of(*instrs) -> CFG:
    """Shortcut: build the CFG of a function with the given instructions."""
    return CFG.build_from_function(make_func("test_func", *instrs))


# ===========================================================================
# BasicBlock
# ===========================================================================

class TestBasicBlock:

    def test_initial_state(self):
        bb = BasicBlock(id=0)
        assert bb.id == 0
        assert bb.instructions == []
        assert bb.predecessors == []
        assert bb.successors == []

    def test_is_empty_true(self):
        bb = BasicBlock(id=0)
        assert bb.is_empty()

    def test_is_empty_false(self):
        bb = BasicBlock(id=0)
        bb.append(IRReturn())
        assert not bb.is_empty()

    def test_append_and_first_last(self):
        bb = BasicBlock(id=1)
        i1 = IRCopy("t0", "5")
        i2 = IRReturn("t0")
        bb.append(i1)
        bb.append(i2)
        assert bb.first() is i1
        assert bb.last() is i2
        assert len(bb.instructions) == 2

    def test_first_last_empty(self):
        bb = BasicBlock(id=0)
        assert bb.first() is None
        assert bb.last() is None

    def test_label_with_irlabel(self):
        bb = BasicBlock(id=0)
        bb.append(IRLabel("WHILE_START_0"))
        bb.append(IRReturn())
        assert bb.label() == "WHILE_START_0"

    def test_label_without_irlabel(self):
        bb = BasicBlock(id=3)
        bb.append(IRCopy("t0", "1"))
        assert bb.label() == "B3"

    def test_label_empty_block(self):
        bb = BasicBlock(id=7)
        assert bb.label() == "B7"

    def test_str_contains_id_and_label(self):
        bb = BasicBlock(id=2)
        bb.append(IRLabel("IF_END_0"))
        bb.append(IRReturn("t0"))
        s = str(bb)
        assert "Block 2" in s
        assert "IF_END_0" in s

    def test_repr(self):
        bb = BasicBlock(id=5)
        bb.append(IRLabel("LOOP"))
        assert "BasicBlock" in repr(bb)
        assert "5" in repr(bb)
        assert "LOOP" in repr(bb)

    def test_equality_by_identity(self):
        bb1 = BasicBlock(id=0)
        bb2 = BasicBlock(id=0)
        assert bb1 == bb1
        assert bb1 != bb2

    def test_hash_by_identity(self):
        bb1 = BasicBlock(id=0)
        bb2 = BasicBlock(id=0)
        s = {bb1, bb2}
        assert len(s) == 2


# ===========================================================================
# CFG - block structure
# ===========================================================================

class TestCFGEmpty:

    def test_empty_function_zero_blocks(self):
        cfg = cfg_of()
        assert len(cfg.blocks) == 0
        assert cfg.entry is None

    def test_func_name_preserved(self):
        func = make_func("mi_funcion", IRReturn())
        cfg = CFG.build_from_function(func)
        assert cfg.func_name == "mi_funcion"


class TestCFGLinear:
    """Functions with no jumps must produce exactly 1 block."""

    def test_single_return(self):
        cfg = cfg_of(IRReturn())
        assert len(cfg.blocks) == 1
        assert cfg.entry is cfg.blocks[0]

    def test_single_return_no_successors(self):
        cfg = cfg_of(IRReturn())
        assert cfg.blocks[0].successors == []
        assert cfg.blocks[0].predecessors == []

    def test_linear_sequence_one_block(self):
        # t0 = 3 + 4; t1 = t0; return t1
        cfg = cfg_of(
            IRBinOp("t0", "3", BinOp.ADD, "4"),
            IRCopy("t1", "t0"),
            IRReturn("t1"),
        )
        assert len(cfg.blocks) == 1

    def test_linear_has_all_instructions(self):
        i1 = IRBinOp("t0", "a", BinOp.MUL, "b")
        i2 = IRCopy("t1", "t0")
        i3 = IRReturn("t1")
        cfg = cfg_of(i1, i2, i3)
        block = cfg.blocks[0]
        assert block.instructions == [i1, i2, i3]

    def test_function_call_no_split(self):
        # IRCall does NOT split blocks at this level
        cfg = cfg_of(
            IRParam("x"),
            IRCall("t0", "foo", 1),
            IRReturn("t0"),
        )
        assert len(cfg.blocks) == 1


# ===========================================================================
# CFG - if/else
# ===========================================================================

class TestCFGIfElse:
    """
    Typical IF/ELSE structure emitted by IRGenerator:

        0: iffalse t0 goto IF_ELSE_0
        1: t1 = 1                       <- then-branch
        2: goto IF_END_0
        3: IF_ELSE_0:                   <- else-branch
        4: t1 = 0
        5: IF_END_0:                    <- merge
        6: return t1

    Expected leaders: {0, 1, 3, 5}  -> 4 blocks
    """

    @pytest.fixture
    def cfg(self) -> CFG:
        return cfg_of(
            IRIfFalse("t0", "IF_ELSE_0"),   # 0 - leader (first) + jump
            IRCopy("t1", "1"),              # 1 - leader (post-jump)
            IRGoto("IF_END_0"),             # 2 - jump
            IRLabel("IF_ELSE_0"),           # 3 - leader (label target)
            IRCopy("t1", "0"),              # 4
            IRLabel("IF_END_0"),            # 5 - leader (label target)
            IRReturn("t1"),                 # 6
        )

    def test_four_blocks(self, cfg):
        assert len(cfg.blocks) == 4

    def test_entry_is_block_zero(self, cfg):
        assert cfg.entry is cfg.blocks[0]

    def test_block0_last_is_iffalse(self, cfg):
        assert isinstance(cfg.blocks[0].last(), IRIfFalse)

    def test_block0_successors(self, cfg):
        # iffalse -> target (IF_ELSE_0 = B2) + fall-through (B1)  [edge semantics]
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 2
        succ_labels = {s.label() for s in b0.successors}
        assert "IF_ELSE_0" in succ_labels
        assert "B1" in succ_labels

    def test_block1_goto_to_merge(self, cfg):
        # B1: t1=1, goto IF_END_0 -> successor must be IF_END_0 block
        b1 = cfg.blocks[1]
        assert len(b1.successors) == 1
        assert b1.successors[0].label() == "IF_END_0"

    def test_block2_else_fallthrough_to_merge(self, cfg):
        # B2 = IF_ELSE_0: t1=0 -> falls through to IF_END_0 (no goto)
        b2 = cfg.blocks[2]
        assert len(b2.successors) == 1
        assert b2.successors[0].label() == "IF_END_0"

    def test_block3_merge_no_successors(self, cfg):
        # B3 = IF_END_0: return t1 -> no successors
        b3 = cfg.blocks[3]
        assert b3.successors == []

    def test_predecessors_merge_block(self, cfg):
        # IF_END_0 must have 2 predecessors: B1 (goto) and B2 (fall-through)
        b3 = cfg.get_block_by_label("IF_END_0")
        assert b3 is not None
        assert len(b3.predecessors) == 2


# ===========================================================================
# CFG - while loop
# ===========================================================================

class TestCFGWhile:
    """
    Typical WHILE structure:

        0: WHILE_START_0:              <- leader (label target of goto)
        1: t0 = i < 10
        2: iffalse t0 goto WHILE_END_0 <- jump
        3: i = i + 1                   <- leader (post-jump)
        4: goto WHILE_START_0          <- jump
        5: WHILE_END_0:                <- leader (label target)
        6: return 0

    Leaders: {0, 3, 5} -> 3 blocks
    """

    @pytest.fixture
    def cfg(self) -> CFG:
        return cfg_of(
            IRLabel("WHILE_START_0"),           # 0
            IRBinOp("t0", "i", BinOp.LT, "10"),# 1
            IRIfFalse("t0", "WHILE_END_0"),     # 2
            IRBinOp("i", "i", BinOp.ADD, "1"), # 3
            IRGoto("WHILE_START_0"),            # 4
            IRLabel("WHILE_END_0"),             # 5
            IRReturn("0"),                      # 6
        )

    def test_three_blocks(self, cfg):
        assert len(cfg.blocks) == 3

    def test_labels(self, cfg):
        assert cfg.blocks[0].label() == "WHILE_START_0"
        assert cfg.blocks[1].label() == "B1"
        assert cfg.blocks[2].label() == "WHILE_END_0"

    def test_header_successors(self, cfg):
        # B0 (WHILE_START_0): iffalse -> B2 (exit) + fall-through B1 (loop body)
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 2
        succ_labels = {s.label() for s in b0.successors}
        assert "WHILE_END_0" in succ_labels
        assert "B1" in succ_labels

    def test_body_goto_back_edge(self, cfg):
        # B1 (body): goto WHILE_START_0 -> back-edge to B0
        b1 = cfg.blocks[1]
        assert len(b1.successors) == 1
        assert b1.successors[0] is cfg.blocks[0]

    def test_exit_no_successors(self, cfg):
        b2 = cfg.blocks[2]
        assert b2.successors == []

    def test_header_has_back_edge_predecessor(self, cfg):
        # B0 must have B1 as predecessor (back-edge)
        b0 = cfg.blocks[0]
        assert cfg.blocks[1] in b0.predecessors

    def test_header_no_initial_predecessor(self, cfg):
        # B0 is the entry: its only predecessor is B1 (back-edge)
        b0 = cfg.blocks[0]
        assert len(b0.predecessors) == 1
        assert b0.predecessors[0] is cfg.blocks[1]


# ===========================================================================
# CFG - if without else
# ===========================================================================

class TestCFGIfNoElse:
    """
    IF without else:

        0: iffalse t0 goto IF_END_0
        1: t1 = 1                      <- leader
        2: IF_END_0:                   <- leader
        3: return t1

    Leaders: {0, 1, 2} -> 3 blocks
    """

    @pytest.fixture
    def cfg(self) -> CFG:
        return cfg_of(
            IRIfFalse("t0", "IF_END_0"),
            IRCopy("t1", "1"),
            IRLabel("IF_END_0"),
            IRReturn("t1"),
        )

    def test_three_blocks(self, cfg):
        assert len(cfg.blocks) == 3

    def test_entry_two_successors(self, cfg):
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 2

    def test_merge_two_predecessors(self, cfg):
        # IF_END_0 has predecessors: B0 (jump) and B1 (fall-through)
        b2 = cfg.get_block_by_label("IF_END_0")
        assert b2 is not None
        assert len(b2.predecessors) == 2


# ===========================================================================
# CFG - multiple returns
# ===========================================================================

class TestCFGMultipleReturns:
    """
    Function with two returns (early return):

        0: iffalse cond goto ELSE_0
        1: return 1                    <- leader, return
        2: ELSE_0:                     <- leader
        3: return 0
    """

    @pytest.fixture
    def cfg(self) -> CFG:
        return cfg_of(
            IRIfFalse("cond", "ELSE_0"),
            IRReturn("1"),
            IRLabel("ELSE_0"),
            IRReturn("0"),
        )

    def test_three_blocks(self, cfg):
        assert len(cfg.blocks) == 3

    def test_early_return_no_successors(self, cfg):
        b1 = cfg.blocks[1]
        assert isinstance(b1.last(), IRReturn)
        assert b1.successors == []

    def test_else_return_no_successors(self, cfg):
        b2 = cfg.blocks[2]
        assert isinstance(b2.last(), IRReturn)
        assert b2.successors == []


# ===========================================================================
# CFG - utility methods
# ===========================================================================

class TestCFGUtilities:

    def test_get_block_by_label_found(self):
        cfg = cfg_of(
            IRIfFalse("x", "LOOP"),
            IRLabel("LOOP"),
            IRReturn(),
        )
        block = cfg.get_block_by_label("LOOP")
        assert block is not None
        assert block.label() == "LOOP"

    def test_get_block_by_label_not_found(self):
        cfg = cfg_of(IRReturn())
        assert cfg.get_block_by_label("NO_EXISTE") is None

    def test_entry_property(self):
        cfg = cfg_of(IRCopy("t0", "1"), IRReturn("t0"))
        assert cfg.entry is cfg.blocks[0]

    def test_entry_empty_cfg(self):
        cfg = cfg_of()
        assert cfg.entry is None

    def test_str_contains_func_name(self):
        func = make_func("mifuncion", IRReturn())
        cfg = CFG.build_from_function(func)
        assert "mifuncion" in str(cfg)

    def test_dot_format_basic(self):
        cfg = cfg_of(
            IRIfFalse("t0", "END"),
            IRCopy("t1", "1"),
            IRLabel("END"),
            IRReturn("t1"),
        )
        dot = cfg.dot()
        assert "digraph" in dot
        assert "B0" in dot
        assert "->" in dot

    def test_dot_contains_all_blocks(self):
        cfg = cfg_of(
            IRIfFalse("t0", "END"),
            IRCopy("t1", "1"),
            IRLabel("END"),
            IRReturn("t1"),
        )
        dot = cfg.dot()
        for block in cfg.blocks:
            assert f"B{block.id}" in dot

    def test_no_duplicate_edges(self):
        """A goto jump must not create duplicate edges."""
        cfg = cfg_of(
            IRGoto("TARGET"),
            IRLabel("TARGET"),
            IRReturn(),
        )
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 1

    def test_instruction_count_preserved(self):
        """Total instructions across all blocks must equal those in the original function."""
        instrs = [
            IRBinOp("t0", "a", BinOp.ADD, "b"),
            IRIfFalse("t0", "L"),
            IRCopy("t1", "1"),
            IRGoto("END"),
            IRLabel("L"),
            IRCopy("t1", "0"),
            IRLabel("END"),
            IRReturn("t1"),
        ]
        func = make_func("f", *instrs)
        cfg = CFG.build_from_function(func)
        total = sum(len(b.instructions) for b in cfg.blocks)
        assert total == len(instrs)
