import numpy as np
import matplotlib as plt 

class FixedPoint:
    def __init__(self,m ,n):
        self.m = m 
        self.n = n
        self.total_bits = m+n
        self.scale = 2**n
        self.max_int = (2**(self.total_bits-1))-1
        self.min_int = -(2 ** (self.total_bits - 1))


    @property
    def precision(self):
        return 2**(-self.n)
    
    @property 
    def max_val(self):
        return self.max_int/self.scale
    
    @property
    def min_val(self):
        return self.min_int/self.scale
    
    def from_float(self,x):
        scaled = np.round(np.array(x,dtype = np.float64)*self.scale)
        return np.clip(scaled, self.min_int,self.max_int).astype(np.int32)
    
    def to_float(self,x_int):
        return np.array(x_int, dtype=np.float64) / self.scale
    
    def saturate(self,x_int):
        return np.clip(x_int, self.min_int, self.max_int).astype(np.int32)
    
    def add(self, a_int, b_int):
        result = a_int.astype(np.int64) + b_int.astype(np.int64)
        return self.saturate(result)
    
    def multiply(self, a_int, b_int):
        result = a_int.astype(np.int64) * b_int.astype(np.int64)
        result = result >> self.n
        return self.saturate(result)
    
    def quantize_array(self, x_float):
        """Full round-trip: float → int repr → back to float (shows quantization error)."""
        return self.to_float(self.from_float(x_float))

    def __repr__(self):
        return (f"FixedPoint Q{self.m}.{self.n} | "
                f"range=[{self.min_val:.4f}, {self.max_val:.4f}] | "
                f"precision={self.precision:.6f}")



fp_q17 = FixedPoint(1, 7)
fp_q44 = FixedPoint(4, 4)

print(fp_q17)
print(fp_q44)

# test Q1.7 addition
a = fp_q17.from_float(np.array([0.5]))
b = fp_q17.from_float(np.array([0.25]))
result_int = fp_q17.add(a, b)
print(f"Q1.7: 0.5 + 0.25 = {fp_q17.to_float(result_int)}")   # should be 0.75

# test Q4.4 multiplication
a = fp_q44.from_float(np.array([2.0]))
b = fp_q44.from_float(np.array([3.0]))
result_int = fp_q44.multiply(a, b)
print(f"Q4.4: 2.0 × 3.0 = {fp_q44.to_float(result_int)}")    # should be 6.0

# test saturation — this should not crash, should clamp
a = fp_q17.from_float(np.array([0.99]))
b = fp_q17.from_float(np.array([0.99]))
result_int = fp_q17.add(a, b)
print(f"Q1.7: 0.99 + 0.99 = {fp_q17.to_float(result_int)}")  # should be 0.9921 (saturated)