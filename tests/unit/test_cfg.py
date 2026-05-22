"""
tests/unit/test_cfg.py
======================
Pruebas unitarias para BasicBlock y CFG (feature/ir-basic-blocks-cfg).

La IR se construye a mano (sin pasar por el parser ni el IRGenerator)
para que los tests sean rapidos, deterministas y no dependan de
la gramatica ANTLR.

Casos cubiertos
---------------
  BasicBlock
    - creacion y atributos iniciales
    - append / first / last / is_empty
    - label() con y sin IRLabel como primera instruccion
    - __str__ y __repr__
    - igualdad por identidad (hash/eq)

  CFG - casos estructurales
    1. Funcion vacia             -> 0 bloques
    2. Solo return               -> 1 bloque, sin sucesores
    3. Secuencia lineal          -> 1 bloque (sin saltos)
    4. If/else simple            -> 4 bloques, aristas correctas
    5. While loop                -> 3 bloques, arista de vuelta (back-edge)
    6. If sin else               -> 3 bloques
    7. Llamada a funcion         -> no rompe bloques
    8. Multiples returns         -> bloques sin sucesor por cada return
    9. Labels no alcanzadas      -> no crean bloques extra
   10. CFG.dot()                 -> formato DOT valido (contiene nodos y aristas)
   11. get_block_by_label        -> busca por nombre de etiqueta
   12. entry property            -> primer bloque
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
    """Crea una IRFunction con la lista de instrucciones dada."""
    func = IRFunction(name=name, params=[], return_type="int")
    for instr in instrs:
        func.emit(instr)
    return func


def cfg_of(*instrs) -> CFG:
    """Atajo: construye el CFG de una funcion con las instrucciones dadas."""
    return CFG.build_from_function(make_func("test_func", *instrs))


# ===========================================================================
# SECCION 1: BasicBlock
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
# SECCION 2: CFG - estructura de bloques
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
    """Funciones sin ningun salto: deben producir exactamente 1 bloque."""

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
        # Las IRCall NO rompen bloques en este nivel
        cfg = cfg_of(
            IRParam("x"),
            IRCall("t0", "foo", 1),
            IRReturn("t0"),
        )
        assert len(cfg.blocks) == 1


# ===========================================================================
# SECCION 3: CFG - if/else
# ===========================================================================

class TestCFGIfElse:
    """
    Estructura IF/ELSE tipica emitida por el IRGenerator:

        0: iffalse t0 goto IF_ELSE_0
        1: t1 = 1                       <- then-branch
        2: goto IF_END_0
        3: IF_ELSE_0:                   <- else-branch
        4: t1 = 0
        5: IF_END_0:                    <- merge
        6: return t1

    Lideres esperados: {0, 1, 3, 5}  -> 4 bloques
    """

    @pytest.fixture
    def cfg(self) -> CFG:
        return cfg_of(
            IRIfFalse("t0", "IF_ELSE_0"),   # 0 - lider (primero) + jump
            IRCopy("t1", "1"),              # 1 - lider (post-jump)
            IRGoto("IF_END_0"),             # 2 - jump
            IRLabel("IF_ELSE_0"),           # 3 - lider (label target)
            IRCopy("t1", "0"),              # 4
            IRLabel("IF_END_0"),            # 5 - lider (label target)
            IRReturn("t1"),                 # 6
        )

    def test_four_blocks(self, cfg):
        assert len(cfg.blocks) == 4

    def test_entry_is_block_zero(self, cfg):
        assert cfg.entry is cfg.blocks[0]

    def test_block0_last_is_iffalse(self, cfg):
        assert isinstance(cfg.blocks[0].last(), IRIfFalse)

    def test_block0_successors(self, cfg):
        # iffalse -> target (IF_ELSE_0 = B2) + fall-through (B1)
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 2
        succ_labels = {s.label() for s in b0.successors}
        assert "IF_ELSE_0" in succ_labels
        assert "B1" in succ_labels

    def test_block1_goto_to_merge(self, cfg):
        # B1: t1=1, goto IF_END_0 -> sucesor debe ser el bloque IF_END_0
        b1 = cfg.blocks[1]
        assert len(b1.successors) == 1
        assert b1.successors[0].label() == "IF_END_0"

    def test_block2_else_fallthrough_to_merge(self, cfg):
        # B2 = IF_ELSE_0: t1=0 -> cae a IF_END_0 (no hay goto)
        b2 = cfg.blocks[2]
        assert len(b2.successors) == 1
        assert b2.successors[0].label() == "IF_END_0"

    def test_block3_merge_no_successors(self, cfg):
        # B3 = IF_END_0: return t1 -> sin sucesor
        b3 = cfg.blocks[3]
        assert b3.successors == []

    def test_predecessors_merge_block(self, cfg):
        # El bloque IF_END_0 debe tener 2 predecesores: B1 (goto) y B2 (fall)
        b3 = cfg.get_block_by_label("IF_END_0")
        assert b3 is not None
        assert len(b3.predecessors) == 2


# ===========================================================================
# SECCION 4: CFG - while loop
# ===========================================================================

class TestCFGWhile:
    """
    Estructura WHILE tipica:

        0: WHILE_START_0:              <- lider (label target de goto)
        1: t0 = i < 10
        2: iffalse t0 goto WHILE_END_0 <- jump
        3: i = i + 1                   <- lider (post-jump)
        4: goto WHILE_START_0          <- jump
        5: WHILE_END_0:                <- lider (label target)
        6: return 0

    Lideres: {0, 3, 5} -> 3 bloques
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
        # B0 (WHILE_START_0): iffalse -> B2 (exit) + fall-through B1 (body)
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 2
        succ_labels = {s.label() for s in b0.successors}
        assert "WHILE_END_0" in succ_labels
        assert "B1" in succ_labels

    def test_body_goto_back_edge(self, cfg):
        # B1 (cuerpo): goto WHILE_START_0 -> back-edge a B0
        b1 = cfg.blocks[1]
        assert len(b1.successors) == 1
        assert b1.successors[0] is cfg.blocks[0]

    def test_exit_no_successors(self, cfg):
        b2 = cfg.blocks[2]
        assert b2.successors == []

    def test_header_has_back_edge_predecessor(self, cfg):
        # B0 debe tener B1 como predecesor (arista de vuelta)
        b0 = cfg.blocks[0]
        assert cfg.blocks[1] in b0.predecessors

    def test_header_no_initial_predecessor(self, cfg):
        # B0 es el entry: no tiene predecesor externo
        # Su unico predecesor es B1 (back-edge)
        b0 = cfg.blocks[0]
        assert len(b0.predecessors) == 1
        assert b0.predecessors[0] is cfg.blocks[1]


# ===========================================================================
# SECCION 5: CFG - if sin else
# ===========================================================================

class TestCFGIfNoElse:
    """
    IF sin else:

        0: iffalse t0 goto IF_END_0
        1: t1 = 1                      <- lider
        2: IF_END_0:                   <- lider
        3: return t1

    Lideres: {0, 1, 2} -> 3 bloques
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
        # IF_END_0 tiene predecesores: B0 (salto) y B1 (fall-through)
        b2 = cfg.get_block_by_label("IF_END_0")
        assert b2 is not None
        assert len(b2.predecessors) == 2


# ===========================================================================
# SECCION 6: CFG - multiples returns
# ===========================================================================

class TestCFGMultipleReturns:
    """
    Funcion con dos returns (early return):

        0: iffalse cond goto ELSE_0
        1: return 1                    <- lider, return
        2: ELSE_0:                     <- lider
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
# SECCION 7: CFG - metodos utilitarios
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
        """Un salto goto no debe crear aristas duplicadas."""
        cfg = cfg_of(
            IRGoto("TARGET"),
            IRLabel("TARGET"),
            IRReturn(),
        )
        b0 = cfg.blocks[0]
        assert len(b0.successors) == 1

    def test_instruction_count_preserved(self):
        """El total de instrucciones en todos los bloques debe ser el mismo
        que en la funcion original."""
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
