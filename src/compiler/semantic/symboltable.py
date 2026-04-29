class SymbolTable:
    WORD_SIZE = 4

    def __init__(self):
        self.symbols = {}
        self.references = {}

        self.current_scope = "global"
        self.scope_stack = ["global"]

        self.next_global_address = 0x100
        self.next_local_address = 0x200

    def enter_scope(self, scope_name, reset_local=False):
        self.scope_stack.append(scope_name)
        self.current_scope = scope_name

        if reset_local:
            self.next_local_address = 0x200

    def exit_scope(self):
        if len(self.scope_stack) == 1:
            raise Exception("Error: cannot exit global scope")

        self.scope_stack.pop()
        self.current_scope = self.scope_stack[-1]

    def allocate_address(self, size=1):
        byte_size = size * self.WORD_SIZE

        if self.current_scope == "global":
            address = self.next_global_address
            self.next_global_address += byte_size
            return address

        address = self.next_local_address
        self.next_local_address += byte_size
        return address

    def declare_variable(self, name, type_name, line, size=1):
        key = (self.current_scope, name)

        if key in self.symbols:
            raise Exception(
                f"Error line {line}: variable '{name}' already declared "
                f"in scope '{self.current_scope}'"
            )

        address = self.allocate_address(size)

        self.symbols[key] = {
            "name": name,
            "kind": "variable",
            "type": type_name,
            "scope": self.current_scope,
            "address": address,
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

        address = self.allocate_address()

        self.symbols[key] = {
            "name": name,
            "kind": "parameter",
            "type": type_name,
            "scope": self.current_scope,
            "address": address,
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