"""
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
"""

from ipaddress import ip_address

import math
import os 

file_dir = os.path.dirname(os.path.realpath(__file__))
p4src_folder = os.path.join(os.path.dirname(file_dir), "p4src")

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

print("Output: p4src/table-alpha.p4.")
with open(os.path.join(p4src_folder, "table-alpha.p4"),"w") as alpha_table_file:

    for alpha_range_id, alpha_range_values in alpha_ranges.items():
        alpha_table_file.writelines("(bit<16>){}..(bit<16>){} : set_alpha_range({});\n".format(
            alpha_range_values[0], alpha_range_values[1], alpha_range_id
        ))


print("Output: p4src/table-beta.p4.")
with open(os.path.join(p4src_folder, "table-beta.p4"),"w") as beta_table_file:

    for beta_range_id, beta_range_values in beta_ranges.items():
        beta_table_file.writelines("(bit<16>){}..(bit<16>){} : set_beta_range({});\n".format(
            beta_range_values[0], beta_range_values[1], beta_range_id
        ))
