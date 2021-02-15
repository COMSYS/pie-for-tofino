"""
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
"""

from ipaddress import ip_address
import math


"""
Computation of the drop probability is split across 3 tables.

The computation of the drop probability itself is done in the table compute_drop_probability_update.

For this, we first determine range regions of diff_to_target and diff_to_prev in two additional tables, alpha_range and beta_range.
Each range is then assigned an integer number which is then used for an exact lookup in the compute_drop_probability_update table.

This is why we here first define the relation between integer number and corresponding range for compute_drop_probability_update.
"""

"""
For alpha, we use the 16 bits of diff_to_target.
"""
values_for_alpha_range = 300

alpha_ranges = {}
id_counter = 0

interval_start = -125
interval_end = -124

stepSize = (500.0)/(values_for_alpha_range)

while interval_end < -9:

    start_for_range_lookup = interval_start
    end_for_range_lookup = interval_end
    
    alpha_ranges[id_counter] = (start_for_range_lookup, end_for_range_lookup)
    
    id_counter += 1
    interval_start += 2
    interval_end += 2

interval_start = -9
interval_end = -9

while interval_end < 10:

    start_for_range_lookup = interval_start
    end_for_range_lookup = interval_end
    alpha_ranges[id_counter] = (start_for_range_lookup, end_for_range_lookup)

    id_counter += 1
    interval_start += 1 
    interval_end += 1

interval_start = 10
interval_end = 11

while interval_end < 351 or len(alpha_ranges.keys()) < values_for_alpha_range:

    start_for_range_lookup = interval_start
    end_for_range_lookup = interval_end
    
    alpha_ranges[id_counter] = (start_for_range_lookup, end_for_range_lookup)
    
    id_counter += 1
    interval_start += 2
    interval_end += 2


"""
For beta, we use the 16 bits of diff_to_prev.
"""
largest_val = 600
smallest_val = -600

beta_ranges = {}
id_counter = 0

interval_start = -600
interval_end = -597

while interval_end < 0:

    start_for_range_lookup = interval_start
    end_for_range_lookup = interval_end
    
    beta_ranges[id_counter] = (start_for_range_lookup, end_for_range_lookup)
    
    id_counter += 1
    interval_start += 4
    interval_end += 4

beta_ranges[id_counter] = (0, 0)
id_counter += 1
interval_start = 1
interval_end = 4

while interval_end < 601:

    start_for_range_lookup = interval_start
    end_for_range_lookup = interval_end
    
    beta_ranges[id_counter] = (start_for_range_lookup, end_for_range_lookup)
    
    id_counter += 1
    interval_start += 4
    interval_end += 4




"""
Now combining this with the compute_drop_probability_update table.
Here, we have 2 match keys:
meta.alpha_range: exact;
meta.beta_range: exact;

From these range IDs of alpha & beta, we also have to determine whether to increase or decrease drop_prob.

The action data that we return is the following

    action set_probability(bit<32> probability, bit<1> increase) {
        meta.drop_probability_update = probability;
        meta.drop_probability_increase = increase;
    }

This means that we have to compute the update value (in 32 bit) and further also indicate whether we have to increase the probability or not.
"""


compute_drop_probability_lookups_prelim = []


MS_TO_US = 1000.0
S_TO_US = 1000000.0
US = 1.0
T_UPDATE=15 * MS_TO_US
QDELAY_REF=15 * MS_TO_US

MAX_PROB=2**32-1
alpha=0.125
beta=1.25

QDELAY_REF_NEW = 125*US
T_UPDATE_NEW = 150*US

while T_UPDATE > T_UPDATE_NEU:
    T_UPDATE = T_UPDATE / 2.0
    beta= beta+alpha/4.0
    alpha=alpha/2.0

alpha = alpha * QDELAY_REF/QDELAY_REF_NEW
beta = beta * QDELAY_REF/QDELAY_REF_NEW

print("T_UPDATE:", T_UPDATE)
print("Alpha:", alpha)
alpha_scaled = alpha * (MAX_PROB/S_TO_US)
print("Alpha_scaled:", alpha_scaled)
alpha_scaled_shift = math.log(alpha*(MAX_PROB/S_TO_US))/math.log(2)
print("Alpha_scaled_shift:", alpha_scaled_shift)
print("Beta:", beta)
beta_scaled = beta * (MAX_PROB/S_TO_US)
print("Beta_scaled:", beta_scaled)
beta_scaled_shift = math.log(beta*(MAX_PROB/S_TO_US))/math.log(2)
print("Beta_scaled_shift:", beta_scaled_shift)


alpha = alpha_scaled
beta = beta_scaled

max_prob = 0

for beta_range_id, beta_range_values in beta_ranges.items():
    
    for alpha_range_id, alpha_range_values in alpha_ranges.items():
        
        alpha_term = float(float(alpha_range_values[1])+float(alpha_range_values[0])/2)
        alpha_term = alpha * alpha_term

        beta_term = float(float(beta_range_values[1])+float(beta_range_values[0])/2)
        beta_term = beta * beta_term

        probability_update = alpha_term + beta_term
        probability_update = math.trunc(math.floor((probability_update)*10 ** 0 + 0.5) / 10 ** 0)

        if probability_update < 0:
            probability_increase = 0
        else:
            probability_increase = 1

        probability_update = abs(probability_update)
        if probability_update > max_prob:
            max_prob = probability_update

        compute_drop_probability_lookups_prelim.append((alpha_range_id, beta_range_id, probability_update, probability_increase))


"""
On Tofino, we draw a random 32-bit unsigned integer number, i.e., a number in [0, 4294967296-1].
Thus, we have to scale [-1,1] to the range [0, 4294967296-1]
"""
max_on_tofino = float(4294967296-1)
min_on_tofino = float(0)
range_on_tofino = max_on_tofino-min_on_tofino

max_in_computation = float(max_prob)
min_in_computation = float(0)
range_in_computation = max_in_computation - min_in_computation

counter = 0 
compute_drop_probability_lookups = []
scaling_needed = False
for (alpha_range_id, beta_range_id, probability_update, probability_increase) in compute_drop_probability_lookups_prelim:
        
    probability_to_be_set = (math.trunc(math.floor(probability_update*10 ** 0 + 0.5) / 10 ** 0))

    compute_drop_probability_lookups.append((alpha_range_id, beta_range_id, probability_to_be_set, probability_increase))
    counter = counter + 1


"""
Now put all the stuff onto Tofino
"""

drop_probability_update_table = bfrt.pie_table.pipe.Egress.compute_drop_probability_update

print("Fill table: compute_drop_probability_update")

for values in compute_drop_probability_lookups:
    drop_probability_update_table.add_with_set_probability(
                                                alpha_range=values[0], 
                                                beta_range=values[1],
                                                increase=values[3],
                                                probability=values[2])
