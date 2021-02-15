/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

#ifndef _EGRESS_P4_
#define _EGRESS_P4_

parser EgressParser(
    packet_in pkt,
    out egress_headers_t hdr,
    out egress_meta_t meta,
    out egress_intrinsic_metadata_t eg_intr_md
) {
    state start {
        pkt.extract(eg_intr_md);
        pkt.extract(meta.bridge);

        meta.drop_probability = meta.bridge.drop_probability;
        meta.queue_delay = 0;

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
        transition accept;
    }
}

control Egress(
    inout egress_headers_t hdr,
    inout egress_meta_t meta,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_oport_md
) {
    Register<bit<16>, bit>(1) delay_reg;

    RegisterAction<bit<16>, bit, bool>(delay_reg) set_delay_action = {
        void apply(inout bit<16> reg_data, out bool result) {
            reg_data = (bit<16>) meta.queue_delay_for_storing[25:10];
        }
    };
    RegisterAction<bit<16>, bit, bit<16>>(delay_reg) get_previous_delay = {
        void apply(inout bit<16> reg_data, out bit<16> result) {
            result = reg_data;
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



    apply {


        /*
        * 1. Compute the current queue delay
        * This queue delay is only used if we do not have PIE control traffic.
        *
        * 2. Determine whether we have a valid UDP packet
        *
        */

        meta.queue_delay_for_storing = (bit<32>)(eg_prsr_md.global_tstamp - meta.bridge.ingress_global_tstamp);
        meta.isPIEPacket = (bit<1>) hdr.udp.isValid();


        /*
        * If we have a PIE control packet:
        * Retrieve the last stored delay
        * 
        * If we do not have a PIE control packet:
        * Set the delay of the current packet as the last observed delay
        */
        if (hdr.udp.isValid() && hdr.udp.PIE_Identifier == 0x2323){
            meta.queue_delay = (bit<32>) get_previous_delay.execute(0);
        } else{
            set_delay_action.execute(0);
        }


        /* 
         * Apply the udp table.
         *
         * Essentially: If we have a PIE control packet, write all the PIE information as debug/logging into the packet
         *
         */ 
        udp_table.apply();
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
