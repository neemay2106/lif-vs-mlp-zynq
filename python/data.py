import torch
import torch.nn as nn
import torchvision
import torchvision.transforms as transforms
import numpy as np

torch.manual_seed(21)  # SAME seed as Step 0, so the encoding matches exactly what the model saw internally

transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize((0.1307,), (0.3081,))
])

train_data = torchvision.datasets.MNIST('/Users/neemayrajan/Documents/Project_2/data', train=True, download=False, transform=transform)
test_data  = torchvision.datasets.MNIST('/Users/neemayrajan/Documents/Project_2/data', train=False, download=False, transform=transform)

x, y = test_data[88]
print(y)  # or any index
x_flat = x.view(-1)
x_clamp = torch.clamp(x_flat, 0, 1)
spike_in_t0 = torch.bernoulli(x_clamp)  # one timestep's worth, 784 bits

print(spike_in_t0.sum().item(), "active spikes out of 784")

np.savetxt("spikes.txt", spike_in_t0.numpy(), fmt="%d")



T = 25
x_clamp = torch.clamp(x_flat, 0, 1)

all_timesteps = []
for t in range(T):
    spk = torch.bernoulli(x_clamp).squeeze().tolist()  # 784 bits for this timestep
    all_timesteps.append(spk)
    with open(f"spike/spikes_t{t}.txt", "w") as f:
        for bit in spk:
            f.write(f"{int(bit)}\n")