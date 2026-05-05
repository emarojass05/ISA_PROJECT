class FixupTable:
    def __init__(self):
        self.fixups = []

    def add_fixup(self, instruction_index, label_name, jump_type=None):
        self.fixups.append({
            "instruction_index": instruction_index,
            "label_name": label_name,
            "jump_type": jump_type
        })

    def get_fixups(self):
        return self.fixups

    def clear(self):
        self.fixups.clear()