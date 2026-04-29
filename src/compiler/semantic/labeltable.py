class LabelTable:
    def __init__(self):
        self.labels = {}

    def define_label(self, label_name, address):
        if label_name in self.labels:
            raise Exception(f"Error: label '{label_name}' already defined")

        self.labels[label_name] = address

    def get_label_address(self, label_name):
        if label_name not in self.labels:
            raise Exception(f"Error: label '{label_name}' was not defined")

        return self.labels[label_name]

    def has_label(self, label_name):
        return label_name in self.labels

    def get_labels(self):
        return self.labels