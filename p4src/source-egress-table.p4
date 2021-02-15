/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

/*

This file provides PIE<sub>Table</sub>-specific components to the general egress pipeline defined in egress_common_skeleton.

The first part (GENERAL_DEFINITIONS) hereby provides general definitions.

The second part (REGISTER_TABLE_DEFINITIONS) provides Egress-intrinsic definitions of tables, actions, registers and register actions.

The third part (CONTROL_FLOW) provides the actual Egress Control Flow, utilizing definitions of the first two parts as well as general definitions from egress_common_skeleton.

*/



#ifdef GENERAL_DEFINITIONS

#endif


#ifdef REGISTER_TABLE_DEFINITIONS

    action set_alpha_range(bit<16> alpha_range){
        meta.alpha_range = alpha_range;
    }

    table alpha_range {
        key = {
            meta.diff_to_target : range;
        }
        actions = {
            set_alpha_range;
        }        
        const entries = {
            #include "table-alpha.p4"
        }
        default_action = set_alpha_range(0);
	    size = 400;
    }

    action set_beta_range(bit<16> beta_range){
        meta.beta_range = beta_range;
    }

     
    table beta_range {
        key = {
            meta.diff_to_old_queue_delay : range;
        }
        actions = {
            set_beta_range;
        }
        const entries = {
            #include "table-beta.p4"
        }
        default_action = set_beta_range(0);
	    size = 400;
    }

    action set_probability(bit<32> probability, bit<1> increase) {
        meta.drop_probability_update = probability;
        meta.drop_probability_increase = increase;
    }

    table compute_drop_probability_update {
        key = {
            meta.alpha_range: exact;
            meta.beta_range: exact;
        }
        actions = {
            set_probability;
        }

        // Probabilities are filled dynamically at the start using the controlplane
        default_action = set_probability(0, 0);
	    size = 100000;
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
        meta.diff_to_old_queue_delay = (bit<16>) get_difference_to_last_sampled_delay.execute(0);
        meta.diff_to_target = (bit<16>) get_difference_to_target.execute(0);
    }else{
        set_previous_delay.execute(0);
    }
            

    /*
     * This branch is only needed if we have a PIE control packet.
     * 
     * Look up the range IDs for alpha and beta based on diff_to_old_queue_delay and diff_to_target
     */        
    alpha_range.apply();
    beta_range.apply(); 
    
    /*
     * This branch is only needed if we have a PIE control packet.
     * 
     * Based on the alpha and beta range IDs look up the drop probability update
     */   
    compute_drop_probability_update.apply();
    

    /*
     * Actually update the drop probability
     * 
     * 1. If we have a PIE control packet and
     * a) the drop probability should be increased -> do that with sadd
     * b) the drop probability should be decreased -> do that with ssub
     *
     * 2. If we don't have a PIE control packet
     * Read out the current drop probability 
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
     * Compute whether the packet is to be dropped.
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
