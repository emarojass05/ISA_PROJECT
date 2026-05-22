class SymbolTable:
    WORD_SIZE = 4

    # Frame layout (offsets from sp after frame allocation):
    #   sp+0  : saved ra  (reserved, NOT in symbol table)
    #   sp+4  : first parameter or local variable
    #   sp+8  : second parameter or local variable
    #   ...
    # Local variables use frame offsets; globals use absolute addresses.

    def __init__(self):
        self.symbols = {}
        self.references = {}

        self.current_scope = "global"
        self.scope_stack = ["global"]

        self.next_global_address = 0x100
        # next_frame_offset starts at 4 (offset 0 is reserved for saved ra)
        self.next_frame_offset = 4

    def enter_scope(self, scope_name, reset_local=False):
        self.scope_stack.append(scope_name)
        self.current_scope = scope_name

        if reset_local:
            # Each function gets its own fresh frame starting at offset 4
            self.next_frame_offset = 4

    def exit_scope(self):
        if len(self.scope_stack) == 1:
            raise Exception("Error: cannot exit global scope")

        self.scope_stack.pop()
        self.current_scope = self.scope_stack[-1]

    def allocate_address(self, size=1):
        """Returns (address_or_offset, is_local)."""
        byte_size = size * self.WORD_SIZE

        if self.current_scope == "global":
            address = self.next_global_address
            self.next_global_address += byte_size
            return address, False

        # Local scope: frame-relative offset
        offset = self.next_frame_offset
        self.next_frame_offset += byte_size
        return offset, True

    def declare_variable(self, name, type_name, line, size=1):
        key = (self.current_scope, name)

        if key in self.symbols:
            raise Exception(
                f"Error line {line}: variable '{name}' already declared "
                f"in scope '{self.current_scope}'"
            )

        address, is_local = self.allocate_address(size)

        self.symbols[key] = {
            "name": name,
            "kind": "variable",
            "type": type_name,
            "scope": self.current_scope,
            "address": address,
            "is_local": is_local,
            "size": size,
            "line": line
        }

        self.references[key] = []

        return self.symbols[key]

    def declare_parameter(self, name, type_name, line):
        key = (self.current_scope, name)

        if key in self.symbols:
            raise Exception(
                f"Error line {line}: parameter '{name}' already declared "
                f"in scope '{self.current_scope}'"
            )

        address, is_local = self.allocate_address()

        self.symbols[key] = {
            "name": name,
            "kind": "parameter",
            "type": type_name,
            "scope": self.current_scope,
            "address": address,
            "is_local": is_local,
            "size": 1,
            "line": line
        }

        self.references[key] = []

        return self.symbols[key]

    def declare_function(self, name, return_type, parameters, line, address=None):
        key = ("global", name)

        if key in self.symbols:
            raise Exception(f"Error line {line}: function '{name}' already declared")

        self.symbols[key] = {
            "name": name,
            "kind": "function",
            "type": return_type,
            "scope": "global",
            "address": address,
            "parameters": parameters,
            "line": line
        }

        self.references[key] = []

        return self.symbols[key]

    def lookup(self, name):
        for scope_name in reversed(self.scope_stack):
            key = (scope_name, name)

            if key in self.symbols:
                return key, self.symbols[key]

        key = ("global", name)

        if key in self.symbols:
            return key, self.symbols[key]

        return None, None

    def add_reference(self, name, line):
        key, symbol = self.lookup(name)

        if symbol is None:
            raise Exception(f"Error line {line}: '{name}' was not declared")

        self.references[key].append(line)

        return symbol

    def get_symbols(self):
        return self.symbols

    def get_references(self):
        return self.references
