import numpy as np 
import torchvision
import torchvision.transforms as transforms
from fixed_point import FixedPoint


# Load MNIST
mnist = torchvision.datasets.MNIST(
    root="./data",
    train=True,
    download=True,
    transform=transforms.ToTensor()
)

# Get the first image
image, label = mnist[89]
print(label)
flat_np = image.view(-1).numpy()

print(flat_np.shape)

fp_q17 = FixedPoint(1, 7)

flat_q17 = fp_q17.from_float(flat_np)

print(flat_q17)

with open("mnist_89_q17.hex", "w") as f:
    for value in flat_q17:
        value_int = int(value) & 0xFF
        f.write(f"{value_int:02X}\n")

print("Created mnist_89_q17.hex")
print("Number of lines:", len(flat_q17))


with open("/Users/neemayrajan/Documents/Project_2/weights/layer1_weights.hex", "r") as f:
    layer1_weights= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)

with open("/Users/neemayrajan/Documents/Project_2/weights/layer2_weights.hex", "r") as f:
    layer2_weights= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)

with open("/Users/neemayrajan/Documents/Project_2/weights/layer3_weights.hex", "r") as f:
    layer3_weights= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)

with open("/Users/neemayrajan/Documents/Project_2/weights/layer1_bias.hex", "r") as f:
    layer1_bais= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)

with open("/Users/neemayrajan/Documents/Project_2/weights/layer2_bias.hex", "r") as f:
    layer2_bais= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)

with open("/Users/neemayrajan/Documents/Project_2/weights/layer3_bias.hex", "r") as f:
    layer3_bais= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)


def requantize(raw_sum, bias, relu, shift_amt):
    
    raw_sum = raw_sum >> shift_amt
    raw_sum = raw_sum + np.int32(bias)
    if relu:
        raw_sum = max(raw_sum, 0)
    
    return np.int8(np.clip(raw_sum, -128, 127)), raw_sum

def mlp_layer(act_int8, weights_int8, bias_int8, n_neurons, no_inputs, relu=True,shift_amt = 7):
    sum = np.zeros(n_neurons, dtype=np.int32)

    activations_out = np.zeros(n_neurons, dtype=np.int8)

    for n in range(n_neurons):

        raw_sum = np.int32(0)

        for j in range(no_inputs):
            idx = n * no_inputs + j
            raw_sum += (
                np.int32(act_int8[j]) *
                np.int32(weights_int8[idx])
            )

        # Q2.14 -> Q1.7
        activations_out[n],sum[n] = requantize(raw_sum, bias_int8[n], relu,shift_amt)

        

    return activations_out, sum


# final_l1,sum1 = mlp_layer(flat_q17,layer1_weights,layer1_bais,256,784,relu=True)
# final_l2,sum2 = mlp_layer(final_l1,layer2_weights,layer2_bais,128,256,relu=True)
# final_l3,sum3 = mlp_layer(final_l2,layer3_weights,layer3_bais,10,128,relu=False,shift_amt= 8)

# print(sum1)
# print(sum2)
# print(sum3)
# print(final_l3)
rng = np.random.default_rng()

for i in range(50):
    idx = rng.integers(0, len(mnist))
    image, label = mnist[idx]

    print(label)
    print(image.view(-1).shape)

    flat_np = image.view(-1).numpy()

    fp_q = FixedPoint(1, 7)
    flat_q = fp_q.from_float(flat_np)

    final_l1, sum1 = mlp_layer(flat_q, layer1_weights, layer1_bais,
                               256, 784, relu=True)

    final_l2, sum2 = mlp_layer(final_l1, layer2_weights, layer2_bais,
                               128, 256, relu=True)

    final_l3, sum3 = mlp_layer(final_l2, layer3_weights, layer3_bais,
                               10, 128, relu=False, shift_amt=9)

    print(final_l3)


final_l1, sum1 = mlp_layer(flat_q17, layer1_weights, layer1_bais,
                               256, 784, relu=True)

print(final_l1)

final_l2, sum2 = mlp_layer(final_l1, layer2_weights, layer2_bais,
                               128, 256, relu=True)

print(final_l2)

final_l3, sum3 = mlp_layer(final_l2, layer3_weights, layer3_bais,
                               10, 128, relu=False, shift_amt=9)

print(final_l3)

