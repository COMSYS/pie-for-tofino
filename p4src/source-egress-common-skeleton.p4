/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

#ifndef _EGRESS_P4_
#define _EGRESS_P4_


// Denotes the target delay of PIE
const int TARGET_QUEUE_DELAY_US = 125;



#define GENERAL_DEFINITIONS
#ifdef EGRESS_DATAPLANE_PIE

    #include "source-egress-dataplane.p4"

#elif defined(EGRESS_TABLE_PIE)

    #include "source-egress-table.p4"

#endif
#undef GENERAL_DEFINITIONS


/*
For the dataplane variant, we use the full 32 bit.
For the table variant, use 16 bit to get smaller tables
*/
#ifdef EGRESS_DATAPLANE_PIE
    #define REGISTER_WIDTH 32    
#elif defined(EGRESS_TABLE_PIE)
    #define REGISTER_WIDTH 16  
#endif




// Common Egress pipeline.

control Egress(
    inout egress_headers_t hdr,
    inout egress_meta_t meta,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_oport_md
) {


    /*
        The last_sampled_delay_reg stores the value of the delay that was used for the drop probability calculation in the last sampling round.
        The corresponding RegisterAction returns the difference to this previous delay and stores the new delay in the register.
    */
    Register<bit<REGISTER_WIDTH>, bit>(1) last_sampled_delay_reg;
    RegisterAction<bit<REGISTER_WIDTH>, bit, int<REGISTER_WIDTH>>(last_sampled_delay_reg) get_difference_to_last_sampled_delay = {
        void apply(inout bit<REGISTER_WIDTH> reg_data, out int<REGISTER_WIDTH> result) {
            result = (int<REGISTER_WIDTH>)reg_data - (int<REGISTER_WIDTH>)meta.queue_delay;
            reg_data = meta.queue_delay;
        }
    };

    /* 
        The previous_delay_reg stores the value of the delay that was observed by the last (previous) packet.
        
        For each packet that is not a sampling packet, the observed delay is stored in the register using set_previous_delay.
        As we do not need to have ns accuracy for the delays, we only use bits 25-10 for extracting the delay 
        which roughly corresponds to a minimal resolution of 1us.

        The sampling packets, on the other hand, retrieve the observed delay of the previous packet using get_previous_delay.
    */
    Register<bit<REGISTER_WIDTH>, bit>(1) previous_delay_reg;
    RegisterAction<bit<REGISTER_WIDTH>, bit, bit<REGISTER_WIDTH>>(previous_delay_reg) set_previous_delay = {
        void apply(inout bit<REGISTER_WIDTH> reg_data, out bit<REGISTER_WIDTH> result) {
            reg_data = (bit<REGISTER_WIDTH>) meta.queue_delay_for_storing[25:10];
        }
    };

    RegisterAction<bit<REGISTER_WIDTH>, bit, bit<REGISTER_WIDTH>>(previous_delay_reg) get_previous_delay = {
        void apply(inout bit<REGISTER_WIDTH> reg_data, out bit<REGISTER_WIDTH> result) {
            result = reg_data;
        }
    }; 

    Register<bit<REGISTER_WIDTH>, bit>(1) previous_difference_to_target_reg;
    RegisterAction<bit<REGISTER_WIDTH>, bit, int<REGISTER_WIDTH>>(previous_difference_to_target_reg) get_difference_to_target = {
        void apply(inout bit<REGISTER_WIDTH> reg_data, out int<REGISTER_WIDTH> result) {
            result = (int<REGISTER_WIDTH>)meta.queue_delay - (int<REGISTER_WIDTH>)TARGET_QUEUE_DELAY_US;
            reg_data = meta.queue_delay;
        }
    };


    /* 
        The drop_probability_reg stores the current drop probability with a resolution of 32 bits.

        Packets that are not sampling packets retrieve the current drop probability using get_drop_probability.

        Sampling packets compute a drop probability update using the provided delay information as well as
        different mechanisms (dataplane version VS. table version).
        This drop probability update is stored in meta.drop_probability_update.

        The update is either added to (set_drop_probability_with_sadd) or subtracted from (set_drop_probability_with_ssub) the current drop probability.
        Both operations are performed saturatingly to avoid under- (subtraction) and overflows (addition). 
    */
    Register<bit<32>, bit>(1) drop_probability_reg;
    RegisterAction<bit<32>, bit, bit<32>>(drop_probability_reg) set_drop_probability_with_ssub = {
        void apply(inout bit<32> reg_data, out bit<32> result) {
            reg_data = reg_data |-| (bit<32>) meta.drop_probability_update;
            result = reg_data;
        }
    };
    RegisterAction<bit<32>, bit, bit<32>>(drop_probability_reg) set_drop_probability_with_sadd = {
        void apply(inout bit<32> reg_data, out bit<32> result) {
            reg_data = reg_data |+| (bit<32>) meta.drop_probability_update;
            result = reg_data;
        }
    };
    RegisterAction<bit<32>, bit, bit<32>>(drop_probability_reg) get_drop_probability = {
        void apply(inout bit<32> reg_data, out bit<32> result) {
            result = reg_data;
        }
    };


    /* 
        The rng_reg stores a random number with a resolution of 32 bits which is used to determine the random drops.

        The RegisterAction compare_to_rng hereby compares the current drop probability (as stored in meta.drop_probability) with the 
        random number stored in the register, before storing a new random number (previously stored in meta.random) in the register.
    */
    Random<bit<32>>() rng;
    Register<bit<32>, bit>(1) rng_reg;
    RegisterAction<bit<32>, bit, bool>(rng_reg) compare_to_rng = {
        void apply(inout bit<32> reg_data, out bool result) {
            result = meta.drop_probability > reg_data;
            reg_data = meta.random;
        }
    };

    /*
        Make sure that the correct amount of information is put into the UDP packets in the end.
    */
    action set_udp_stuff() {
            hdr.udp.checksum = 0;
            hdr.udp.ingress_global_tstamp = meta.bridge.ingress_global_tstamp;
            hdr.udp.egress_global_tstamp = eg_prsr_md.global_tstamp;
            hdr.udp.drop_probability = meta.drop_probability;
            hdr.udp.drop_update = meta.drop_probability_update;
            hdr.udp.queue_delay = meta.queue_delay;
            hdr.udp.drop_prob_increase = meta.drop_probability_increase;
        }

    table udp_table {
        key = {
            meta.isPIEPacket: exact;
            hdr.udp.PIE_Identifier: exact;
        }
        actions = {
            set_udp_stuff; NoAction;
        }
        const entries = {
            (1, 0x2323): set_udp_stuff();
        }
        default_action = NoAction;
        size = 2;
    }

    #define REGISTER_TABLE_DEFINITIONS
    #ifdef EGRESS_DATAPLANE_PIE

        #include "source-egress-dataplane.p4"

    #elif defined(EGRESS_TABLE_PIE)

        #include "source-egress-table.p4"

    #endif
    #undef REGISTER_TABLE_DEFINITIONS



    apply {

        #define CONTROL_FLOW
        #ifdef EGRESS_DATAPLANE_PIE

            #include "source-egress-dataplane.p4"

        #elif defined(EGRESS_TABLE_PIE)

            #include "source-egress-table.p4"

        #endif
        #undef CONTROL_FLOW

    }






}



parser EgressParser(
    packet_in pkt,
    out egress_headers_t hdr,
    out egress_meta_t meta,
    out egress_intrinsic_metadata_t eg_intr_md
) {
    state start {
        pkt.extract(eg_intr_md);
        pkt.extract(meta.bridge);

        meta.queue_delay=0;
        meta.diff_to_old_queue_delay=0;
        meta.diff_to_target=0;
        meta.drop_probability=0;
        meta.random=0;

        meta.drop_probability_update=0;
        meta.drop_probability_increase=0;

        meta.alpha_part=0;
        meta.beta_part=0;

        meta.alpha_positive=0;
        meta.beta_positive=0;

        transition l2l3;
    }

    state l2l3 {
        pkt.extract(hdr.ether);
        pkt.extract(hdr.ipv4);

        transition select(hdr.ipv4.protocol) {
            ip_protocol_t.Udp: udp;
            default: accept;
        }
    }

    state udp {
        pkt.extract(hdr.udp);

        hdr.udp.checksum = 0;
        hdr.udp.ingress_global_tstamp = 0;
        hdr.udp.egress_global_tstamp = 0;
        hdr.udp.drop_probability = 0;
        hdr.udp.drop_update = 0;

        transition accept;
    }
}

control EgressDeparser(
    packet_out pkt,
    inout egress_headers_t hdr,
    in egress_meta_t meta,
    in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md
) {
    apply {
        pkt.emit(hdr.ether);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.udp);
    }
}












#endif
