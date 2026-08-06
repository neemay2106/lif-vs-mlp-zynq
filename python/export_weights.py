import os
import torch
import torch.nn as nn
import numpy as np
from fixed_point import FixedPoint

device = torch.device("cpu")


# ---------------- Model ----------------

class MLP(nn.Module):
    def __init__(self):
        super().__init__()

        self.l1 = nn.Linear(784, 256)
        self.l2 = nn.Linear(256, 128)
        self.l3 = nn.Linear(128, 10)

    def forward(self, x):
        x = x.view(-1, 784)
        x = self.l1(x)
        x = self.l2(x)
        x = self.l3(x)
        return x


# ---------------- Load Model ----------------

model = MLP().to(device)

model.load_state_dict(
    torch.load("/Users/neemayrajan/Documents/Project_2/mlp_mnist.pth", map_location=device)
)

model.eval()


# ---------------- Fixed Point ----------------

fp_w = FixedPoint(m=1, n=7)
fp_b = FixedPoint(m=1, n=7)


# ---------------- Export Function ----------------

def export_hex(array, filename, width_bits=8):
    mask = (1 << width_bits) - 1
    hex_digits = width_bits // 4

    with open(filename, "w") as f:
        for value in array.flatten():
            f.write(f"{int(value) & mask:0{hex_digits}X}\n")


# ---------------- Quantize ----------------

os.makedirs("weights", exist_ok=True)

layers = [
    ("layer1", model.l1),
    ("layer2", model.l2),
    ("layer3", model.l3),
]

for name, layer in layers:

    weight = layer.weight.detach().numpy()
    bias = layer.bias.detach().numpy()

    weight_int = fp_w.from_float(weight)
    bias_int = fp_b.from_float(bias)

    export_hex(weight_int, f"weights/{name}_weights.hex")
    export_hex(bias_int, f"weights/{name}_bias.hex")

    print(f"{name}:")
    print(f"  Weight shape : {weight.shape}")
    print(f"  Bias shape   : {bias.shape}")
    print(f"  Exported weights/{name}_weights.hex")
    print(f"  Exported weights/{name}_bias.hex\n")

print("Done.")