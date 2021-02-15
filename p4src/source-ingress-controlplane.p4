/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

#ifndef _INGRESS_P4_
#define _INGRESS_P4_

parser IngressParser(
    packet_in pkt,
    out ingress_headers_t hdrs,
    out ingress_meta_t meta,
    out ingress_intrinsic_metadata_t ig_intr_md
) {
    state start {
        pkt.extract(ig_intr_md);
        pkt.advance(PORT_METADATA_SIZE);

        meta.ingress_port = ig_intr_md.ingress_port;
        meta.random = 0;
        meta.drop_probability=0;

        transition ethernet;
    }

    state ethernet {
        pkt.extract(hdrs.ether);
        pkt.extract(hdrs.ipv4);

        transition accept;
    }
}

control Ingress(
    inout ingress_headers_t hdr,
    inout ingress_meta_t meta,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md
) {

    Register<bit<32>, bit>(1, 0) drop_prob_reg;
    Register<bit<32>, bit>(1) drop_prob_reg_duplicate;

    Random<bit<32>>() rng;

    RegisterAction<bit<32>, _, bool>(drop_prob_reg) load_drop_prob = {
        void apply(inout bit<32> reg_data, out bool result) {
            result = reg_data > meta.random;
        }
    };
    RegisterAction<bit<32>, _, bit<32>>(drop_prob_reg_duplicate) debug_out_drop_prob = {
        void apply(inout bit<32> reg_data, out bit<32> result) {
            result = reg_data;
        }
    };

    action set_qid(QueueId_t qid) {
        ig_tm_md.qid = qid;
    }

    table egress_qid_table { 
        key = { 
            hdr.udp.PIE_Identifier: exact; 
        } 
        actions = { 
            set_qid;
        }
        const entries = {
            0x2323: set_qid(1); /* PIE packet */
        }
        default_action = set_qid(0);
        size = 10;
    }


    action l3_send(PortId_t port) {
        ig_tm_md.ucast_egress_port = port;
    }

    action l3_miss() {
    }

    // Do simple L3 Forwarding
    table l3_forwarding {
        key = {
            hdr.ipv4.dst_addr: exact;
        }
        actions = {
            l3_send;
            l3_miss;
        }
        default_action = l3_miss();
    }

    apply {

        /*
         * 1. Do the forwarding decision (using the L3 table)
         *
         * 2. Determine the queue that is to be used for the traffic manager
         * 2.1 "Normal traffic" is pushed through queue 0
         * 2.2 "PIE Measurement traffic" is pushed through queue 1
         * 
         * 3. Draw a random number to make later make the drop decision
         */

     
        l3_forwarding.apply();
        egress_qid_table.apply();
        meta.random = rng.get();

        /* 
         * Compute whether the packet is to be dropped (using drop probability expressed in [0, U16_MAX])
         *
         * load_drop_prob does two things:
         * 1. Load the current drop probability from the register 
         * 2. Compare the drop probability to the previosuly generated random value (meta.random) 
         *    Set meta.drop to true if the random number is smaller than the drop probability
         *
         * The control plane takes care of scaling the drop probability from [0, 1]
         * to [0, U16_MAX].
         *
         * debug_out_drop_prob just loads the drop probability into another meta field 
         * which is then used by the "PIE Measurement traffic"
         *
         */

        meta.drop = load_drop_prob.execute(0);
        meta.drop_probability = debug_out_drop_prob.execute(0);


        /*
         * Executes the previously computed drop decision based on
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


            // 1. PIE Control/Measurement Packets are not dropped! 
            if (hdr.udp.isValid() && hdr.udp.PIE_Identifier == 0x2323){
                ig_dprsr_md.drop_ctl = 0;
            }
            // 2. Decision was to drop packet -> decide if dropping is active or inactive
            else if (meta.drop) {
                // 2.1
                #ifdef DROPPING_ACTIVE
                    ig_dprsr_md.drop_ctl = 1;
                // 2.2
                #else 
                    ig_dprsr_md.drop_ctl = 0;
                #endif
            // 3.
            } else {
                ig_dprsr_md.drop_ctl = 0;
            }

        /*
         * Write the timestamp as well as the drop probability into the bridge header
         * and set that header to valid so that the information can be passed
         * onto the egress.
         */
            hdr.bridge.ingress_global_tstamp = ig_prsr_md.global_tstamp;
            hdr.bridge.drop_probability = meta.drop_probability;
            hdr.bridge.setValid();
    }
}

control IngressDeparser(
    packet_out pkt,
    inout ingress_headers_t hdr,
    in ingress_meta_t meta,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md
) {
    apply {
        pkt.emit(hdr);
    }
}

#endif
