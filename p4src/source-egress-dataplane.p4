/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

/*

This file provides PIE<sub>DP</sub>-specific components to the general egress pipeline defined in egress_common_skeleton.

The first part (GENERAL_DEFINITIONS) provides general definitions.

The second part (REGISTER_TABLE_DEFINITIONS) provides Egress-intrinsic definitions of tables, actions, registers, and register actions.

The third part (CONTROL_FLOW) provides the actual Egress Control Flow, utilizing definitions of the first two parts as well as general definitions from egress_common_skeleton.

*/


#ifdef GENERAL_DEFINITIONS

    // LEFT SHIFT OF ALPHA
    const int ALPHA_SHIFT = 9;
    // LEFT SHIFT OF BETA
    const int BETA_SHIFT = 19;
#endif




#ifdef REGISTER_TABLE_DEFINITIONS

    action alpha_geq(){
        meta.alpha_geq_beta = 1;
    }
    action beta_greater(){
        meta.alpha_geq_beta = 0;
    }

    table compare_alpha_beta {
        key = {
            meta.beta_alpha_ssubtraction: ternary;
        }
        actions = {
            alpha_geq;
            beta_greater;
        }
        const entries = {
            0xFFFFFFFF &&& 0x80000000 : beta_greater();
            0xFFFFFFFF &&& 0x40000000 : beta_greater();
            0xFFFFFFFF &&& 0x20000000 : beta_greater();
            0xFFFFFFFF &&& 0x10000000 : beta_greater();
            0xFFFFFFFF &&& 0x08000000 : beta_greater();
            0xFFFFFFFF &&& 0x04000000 : beta_greater();
            0xFFFFFFFF &&& 0x02000000 : beta_greater();
            0xFFFFFFFF &&& 0x01000000 : beta_greater();
            0xFFFFFFFF &&& 0x00800000 : beta_greater();
            0xFFFFFFFF &&& 0x00400000 : beta_greater();
            0xFFFFFFFF &&& 0x00200000 : beta_greater();
            0xFFFFFFFF &&& 0x00100000 : beta_greater();
            0xFFFFFFFF &&& 0x00080000 : beta_greater();
            0xFFFFFFFF &&& 0x00040000 : beta_greater();
            0xFFFFFFFF &&& 0x00020000 : beta_greater();
            0xFFFFFFFF &&& 0x00010000 : beta_greater();
            0xFFFFFFFF &&& 0x00008000 : beta_greater();
            0xFFFFFFFF &&& 0x00004000 : beta_greater();
            0xFFFFFFFF &&& 0x00002000 : beta_greater();
            0xFFFFFFFF &&& 0x00001000 : beta_greater();
            0xFFFFFFFF &&& 0x00000800 : beta_greater();
            0xFFFFFFFF &&& 0x00000400 : beta_greater();
            0xFFFFFFFF &&& 0x00000200 : beta_greater();
            0xFFFFFFFF &&& 0x00000100 : beta_greater();
            0xFFFFFFFF &&& 0x00000080 : beta_greater();
            0xFFFFFFFF &&& 0x00000040 : beta_greater();
            0xFFFFFFFF &&& 0x00000020 : beta_greater();
            0xFFFFFFFF &&& 0x00000010 : beta_greater();
            0xFFFFFFFF &&& 0x00000008 : beta_greater();
            0xFFFFFFFF &&& 0x00000004 : beta_greater();
            0xFFFFFFFF &&& 0x00000002 : beta_greater();
            0xFFFFFFFF &&& 0x00000001 : beta_greater();
        }

        default_action = alpha_geq();
	    size = 32;
    }

    action both_increase_prob(){
        meta.drop_probability_update = (bit<32>)meta.alpha_part |+| (bit<32>)meta.beta_part;
        meta.drop_probability_increase = 1;
    }

    action alpha_increases_prob(){
        meta.drop_probability_update = (bit<32>) meta.alpha_part |-| (bit<32>) meta.beta_part;
        meta.drop_probability_increase = 1;
    }

    action beta_decreases_prob(){
        meta.drop_probability_update = (bit<32>) meta.beta_part |-| (bit<32>) meta.alpha_part;
        meta.drop_probability_increase = 0;
    }

    action alpha_decreases_prob(){
        meta.drop_probability_update = (bit<32>) meta.alpha_part |-| (bit<32>) meta.beta_part;
        meta.drop_probability_increase = 0;
    }

    action beta_increases_prob(){
        meta.drop_probability_update = (bit<32>) meta.beta_part |-| (bit<32>) meta.alpha_part;
        meta.drop_probability_increase = 1;
    }

    action both_decrease_prob(){
        meta.drop_probability_update = (bit<32>)meta.alpha_part |+| (bit<32>)meta.beta_part;
        meta.drop_probability_increase = 0;
    }

    table compute_drop_probability_update {
        key = {
            meta.alpha_positive: exact;
            meta.beta_positive: exact;
            meta.alpha_geq_beta: exact;
        }
        actions = {
            both_increase_prob;
            alpha_increases_prob;
            beta_decreases_prob;
            alpha_decreases_prob;
            beta_increases_prob;
            both_decrease_prob;
        }
        const entries = {
            // Alpha and beta part increase drop prob
            (1, 1, 1) : both_increase_prob();
            (1, 1, 0) : both_increase_prob();
            // Subtract beta from alpha
            (1, 0, 1) : alpha_increases_prob();
            // Subtract alpha from beta
            (1, 0, 0) : beta_decreases_prob();
            // Subtract beta from alpha
            (0, 1, 1) : alpha_decreases_prob();
            // Subtract alpha from beta
            (0, 1, 0) : beta_increases_prob();
            // Alpha and beta part decrease drop prob
            (0, 0, 1) : both_decrease_prob();
            (0, 0, 0) : both_decrease_prob();
        }

        default_action = both_increase_prob();
	    size = 8;
    }

#endif




#ifdef CONTROL_FLOW


    /* 
     * 1. Generate random number for the random drop -> Doesn't really matter when it is performed, so do it here.
     * 
     * 2. Compute the current queue delay
     * This queue delay is only used if we do not have PIE control traffic.
     *
     * 3. Determine whether we have a valid UDP packet
     */
    meta.random = rng.get();
    meta.queue_delay_for_storing = (bit<32>)(eg_prsr_md.global_tstamp - meta.bridge.ingress_global_tstamp);
    meta.isPIEPacket = (bit<1>) hdr.udp.isValid();
    

    /*
     * If we have a PIE control packet:
     * 1. Retrieve the last stored delay
     * 2. Compute the difference of that delay to 
     * a) the target delay
     * b) the delay value that was used for the last PIE update 
     * 
     * If we do not have a PIE control packet:
     * - Set the delay of the current packet as the last observed delay
     */
    if (hdr.udp.isValid() && hdr.udp.PIE_Identifier == 0x2323){
        meta.queue_delay = get_previous_delay.execute(0);
        meta.diff_to_old_queue_delay = (int<32>) get_difference_to_last_sampled_delay.execute(0);
        meta.diff_to_target = (int<32>) get_difference_to_target.execute(0);
    }else{
        set_previous_delay.execute(0);
    }


    /*
     * Prepare the alpha & beta part computations by checking the sign of diff_to_target and diff_to_old_queue_delay.
     *
     * Alpha:
     * - Define alpha as positive if diff_to_target is >= 0
     *
     * Beta:
     * - Define beta as positive if diff_to_old_queue_delay >= 0
     *
     */

    if (meta.diff_to_target >= 0){
        // Positive alpha
        meta.alpha_positive = 1;
        meta.alpha_part = (bit<32>) meta.diff_to_target;
    } else{
        // Negative alpha
        meta.alpha_positive = 0;
        meta.alpha_part = (bit<32>) (-meta.diff_to_target);
    }

    if (meta.diff_to_old_queue_delay >= 0){
        // Positive beta
        meta.beta_positive = 1;
        meta.beta_part = (bit<32>) meta.diff_to_old_queue_delay;
        meta.beta_part_temp = (bit<32>) meta.diff_to_old_queue_delay;
    } else{
        // Negative beta
        meta.beta_positive = 0;
        meta.beta_part = (bit<32>) (-meta.diff_to_old_queue_delay);
        meta.beta_part_temp = (bit<32>) (-meta.diff_to_old_queue_delay);
    
    }


    /*
     * Approximate the actual multiplications by alpha and beta using shifts
     */    
    meta.alpha_part = meta.alpha_part << ALPHA_SHIFT;
    meta.beta_part = meta.beta_part << BETA_SHIFT;
        
    /*
     * Now we have calculated the values of the alpha and beta terms.
     * We still need to figure out how to combine them.
     * For this, we first have to find out which of the two terms is larger
     *
     * 1. Compute a saturating substraction of beta |-| alpha = beta_alpha_ssubtraction
     *
     * 2. Do a ternary match on the result beta_alpha_ssubtraction:
     * - if any bit of beta_alpha_ssubtraction is set, beta is bigger
     * - otherwise, alpha is bigger or both have the same value
     *
     */

    meta.beta_alpha_ssubtraction = meta.beta_part |-| meta.alpha_part;
    compare_alpha_beta.apply();
    
    /*
     *
     * Based on our knowledge about the alpha and beta parts,
     * we can now compute the drop probability update.
     * 
     * There are 8 cases, depending on whether 
     * a) alpha/beta are positive or negative
     * b) alpha is greater equal beta or the other way around
     *
     * These cases determine how the drop probability update is computed
     * and whether it is added to/ subtracted from the drop probability 
     *
     */
    
    compute_drop_probability_update.apply();

    // Skip: Scaling of the drop probability update due to the single access rule

    /*
     *
     * If we have a PIE control packet:
     * - Correctly update the drop probability based on the previous results
     *
     * Otherwise:
     * - Read out the current drop probability to actually perform a drop hereafter
     *
     */
    if (hdr.udp.isValid() && meta.drop_probability_increase == 1 && hdr.udp.PIE_Identifier == 0x2323){        
            meta.drop_probability = set_drop_probability_with_sadd.execute(0);
    } else if (hdr.udp.isValid() && hdr.udp.PIE_Identifier == 0x2323){
            meta.drop_probability = set_drop_probability_with_ssub.execute(0);
    } else{
            meta.drop_probability = get_drop_probability.execute(0);
    }
    
    /* 
     * Decide whether the packet is to be dropped.
     *
     * Compare the drop probability to the random value generated in stage 0 (meta.random) 
     *    Set meta.drop to true if the random number is smaller than the drop probability
     *
     */ 

    meta.drop = compare_to_rng.execute(0);



    /*
     * Execute the previously computed drop decision based on
     * what kind of traffic the packet belongs to and how PIE is configured
     *
     * 1. Don't drop PIE Control/Measurement Packets
     *
     * 2. Decision was to drop the packet
     * 2.1 Dropping is active -> set meta field to drop packet
     * 2.2 Dropping is inactive -> set meta field to keep the packet 
     *
     * 3. Decision was to not drop the packet
     */

    if (hdr.udp.isValid() && hdr.udp.PIE_Identifier == 0x2323){
        eg_dprsr_md.drop_ctl = 0;
    }
    else if (meta.drop){
        #ifdef DROPPING_ACTIVE
            eg_dprsr_md.drop_ctl = 1;
        #else 
            eg_dprsr_md.drop_ctl = 0;
        #endif
    }
    else{
        eg_dprsr_md.drop_ctl = 0;
    }


    /* 
     * Apply the udp table.
     *
     * Essentially: If we have a PIE control packet, write all the PIE information as debug/logging into the packet
     *
     */ 

    udp_table.apply();

#endif
