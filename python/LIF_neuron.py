import numpy as np 
import matplotlib.pyplot as plt
from fixed_point import FixedPoint

BETA_FLOAT = 0.95
THRESHOLD = 1 
WEIGHT = 0.35

def lif_neuron_step(spike_in, weights, beta, threshold, mem, skipped_mac_count):
    weights_q8_8 = weights << 1  # Q1.7 -> Q8.8, left shift (extra fractional bit)

    mem_decayed = (mem * beta) >> 8 # Q8.8 * Q8.8 = Q16.16 intermediate, shift back to Q8.8

    if spike_in:
        mem_next = mem_decayed + weights_q8_8
    else:
        mem_next = mem_decayed  # leak happens every cycle regardless of spike_in
        skipped_mac_count += 1 

    spike_out = 1 if mem_next >= threshold else 0
    if spike_out:
        mem_next = 0

    return spike_out, mem_next,skipped_mac_count


fp_w = FixedPoint(1,7)
fp_m = FixedPoint(8,8)

beta_int = fp_m.from_float(np.array([BETA_FLOAT]))[0]
threshold_int = fp_m.from_float(np.array([THRESHOLD]))[0]

weight_int =fp_w.from_float(np.array([WEIGHT]))[0]


def gen_all_zero(n_cycles=10):
    spike_in_seq = [0] * n_cycles
    weight = 0.15  # doesn't matter, no spikes means weight never gets added
    return spike_in_seq, weight

def gen_all_one(n_cycles=10):
    spike_in_seq = [1] * n_cycles
    weight = 0.35  # your known buildup-then-spike weight
    return spike_in_seq, weight

def gen_negative_never_spikes(n_cycles=5):
    spike_in_seq = [1, 1, 0, 1, 0]
    weight = -0.15
    return spike_in_seq, weight

def gen_realistic_density(n_cycles=25, rate=0.208, seed=42):
    rng = np.random.default_rng(seed)
    spike_in_seq = (rng.random(n_cycles) < rate).astype(int).tolist()
    weight = 0.15  # or pull an actual W1 value
    return spike_in_seq, weight


def run_and_export(spike_in_seq, weight_float, filename):
    mem = fp_m.from_float(np.array([0.0]))[0]
    weight_int = fp_w.from_float(np.array([weight_float]))[0]
    skipped = 0
    
    with open(filename, 'w') as f:
        for spike_in in spike_in_seq:
            spike_out, mem,skipped = lif_neuron_step(spike_in, weight_int, beta_int, threshold_int, mem, skipped_mac_count= skipped)
            f.write(f"{spike_in} {spike_out} {mem} {skipped} {weight_int}\n")

seq, w = gen_all_zero()
run_and_export(seq, w, "expected_all_zero.txt")

seq, w = gen_all_one()
run_and_export(seq, w, "expected_all_one.txt")

seq, w = gen_negative_never_spikes()
run_and_export(seq, w, "expected_negative.txt")

seq, w = gen_realistic_density()
run_and_export(seq, w, "expected_realistic.txt")


def lif_layer_step(spike_in_vec, weight_matrix, beta_int, threshold_int, membrane_vec,neurons,inputs_no):
    # weight_matrix: shape (256, 784), already in Q1.7 int form
    # membrane_vec: shape (256,), current membrane state, Q8.8 int form
    # decayed_flags: shape (256,), bool, whether each neuron has decayed this timestep
    spike_out_vec = []
    new_membrane_vec = []
    skipped = 0

    for n in range(neurons):
        mem = membrane_vec[n]
        already_decayed = False
        
        # replicate your exact RTL logic here, input by input
        for i in range(inputs_no):
            spike_in = spike_in_vec[i]
            
            if not already_decayed:
                mem = (mem * beta_int) >> 8
                already_decayed = True
            if mem >= 128:
                print(mem)
                
            
            if spike_in == 1:
                mem = mem + (weight_matrix[n*inputs_no +i] << 1)   # Q1.7 -> Q8.8, same shift as RTL
            else:  
                  skipped += 1
                
        if mem >= threshold_int:
            spike_out = 1 
            
        else:
            spike_out = 0
        
        if spike_out == 1:
            mem = 0
        
        spike_out_vec.append(spike_out)
        new_membrane_vec.append(mem)

    return spike_out_vec, new_membrane_vec, skipped





with open("data_layer/weights/weights_layer1.hex", "r") as f:
    data = np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)
data = data.tolist()


new_membrane = [0] * 256
new_membrane_2 = [0] * 128
new_membrane_3 = [0] * 10

with open("data_layer/weights/weights_layer2.hex", "r") as f:
    data_2= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)
data_2 = data_2.tolist()

with open("data_layer/weights/weights_layer3.hex", "r") as f:
    data_3= np.array([
        x - 0x100 if x >= 0x80 else x
        for x in (int(line.strip(), 16) for line in f)
    ], dtype=np.int8)
data_3 = data_3.tolist()

skip_mac = 0
spike_count = np.zeros(10, dtype=int)
for t in range(0,25):
    x = np.loadtxt(f"/Users/neemayrajan/Documents/Project_2/spike/spikes_t{t}.txt")
    x = x.tolist()

    spikes_out, new_membrane, skipped_mac1 = lif_layer_step(spike_in_vec=x, weight_matrix=data,beta_int=243,threshold_int=256,membrane_vec=new_membrane,neurons=256,inputs_no=784)
    np.savetxt("py_mem_t0.txt", np.array(new_membrane), fmt="%d")
    print("spikes = ",sum(spikes_out))
    spikes_out_2, new_membrane_2, skipped_mac2 = lif_layer_step(spike_in_vec=spikes_out, weight_matrix=data_2,beta_int=243,threshold_int=256,membrane_vec=new_membrane_2,neurons=128,inputs_no=256)
    spikes_out_3, new_membrane_3,skipped_mac3 = lif_layer_step(spike_in_vec=spikes_out_2, weight_matrix=data_3,beta_int=243,threshold_int=256,membrane_vec=new_membrane_3,neurons=10,inputs_no=128)
    print('spikes out', sum(spikes_out_3))
    skip_mac += skipped_mac1 +skipped_mac2 + skipped_mac3

    spike_count += np.array(spikes_out_3)

print("Total spikes over 25 timesteps:")
print(spike_count)
print("total skipped macs", skip_mac)
prediction = np.argmax(spike_count)
print("Prediction:", prediction)