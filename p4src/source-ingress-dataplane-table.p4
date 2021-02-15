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

        transition ethernet;
    }

    state ethernet {
        pkt.extract(hdrs.ether);
        pkt.extract(hdrs.ipv4);

        transition select(hdrs.ipv4.protocol) {
            ip_protocol_t.Udp: udp;
            default: accept;
        }
    }

    state udp {
        pkt.extract(hdrs.udp);
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
         * Stage 0 does two things:
         *
         * 1. Do the forwarding decision (using the static L3 table)
         *
         * 2. Determine the queue that is to be used for the traffic manager
         * 2.1 "Normal traffic" is pushed through queue 0
         * 2.2 "PIE Measurement traffic" is pushed through queue 1
         */

            l3_forwarding.apply();
            egress_qid_table.apply();

        /*
         * Write the timestamp into the bridge header and set that header to valid
         * so that the information can be passed onto the egress.
         */
            hdr.bridge.ingress_global_tstamp = ig_prsr_md.global_tstamp;
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
