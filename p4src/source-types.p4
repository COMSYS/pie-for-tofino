/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

#ifndef _TYPES_P4_
#define _TYPES_P4_

enum bit<16> ether_type_t {
    Ipv4 = 0x0800,
    Ipv6 = 0x86DD
}

header ethernet_h {
    bit<48> dst_addr;
    bit<48> src_addr;
    ether_type_t ether_type;
}

enum bit<8> ip_protocol_t {
    Tcp = 0x06,
    Udp = 0x11
}

header ipv4_h {
    bit<4> version;
    bit<4> ihl;
    bit<6> diffserv;
    bit<2> ecn;
    bit<16> total_len;
    bit<16> identification;
    bit<3> flags;
    bit<13> frag_offset;
    bit<8> ttl;
    ip_protocol_t protocol;
    bit<16> hdr_checksum;
    bit<32> src_addr;
    bit<32> dst_addr;
}

header udp_with_delays_h {
    // Real UDP part
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> len;
    bit<16> checksum;

    // Add measurement fields to the packet

    // Some identifier to distinguish 'PIE' control packets (we use 0x2323 for PIE packets) 
    bit<16> PIE_Identifier;

    bit<48> ingress_global_tstamp;
    bit<48> egress_global_tstamp;

    #ifdef EGRESS_TABLE_PIE
        bit<16> padding_1;
        bit<16> queue_delay;
    #endif
    #ifdef EGRESS_DATAPLANE_PIE
        bit<32> queue_delay;
    #endif
    #ifdef EGRESS_CONTROLPLANE_PIE
        bit<32> queue_delay;
    #endif

    // Current value of the drop probability
    bit<32> drop_probability;
    // Current adjustment value
    bit<32> drop_update;

    bit<15> padding_2;
    // Drop-Prob Up/Down
    bit<1> drop_prob_increase;

    bit<32> ethernet_padding;
}

header bridge_h {
    bit<48> ingress_global_tstamp;
    bit<32> drop_probability;
}

struct ingress_headers_t {
    bridge_h bridge;
    ethernet_h ether;
    ipv4_h ipv4;
    udp_with_delays_h udp;
}

struct ingress_meta_t {
    PortId_t ingress_port;
    bit<32> random;
    bit<32> drop_probability;
    bool drop;
}

struct egress_headers_t {
    ethernet_h ether;
    ipv4_h ipv4;
    udp_with_delays_h udp;
}

struct egress_meta_t {
    bridge_h bridge;
    #ifdef EGRESS_TABLE_PIE
        bit<16> queue_delay;
    #endif
    #ifdef EGRESS_DATAPLANE_PIE
        bit<32> queue_delay;
    #endif
    #ifdef EGRESS_CONTROLPLANE_PIE
        bit<32> queue_delay;
    #endif

    bit<32> queue_delay_for_storing;

    #ifdef EGRESS_TABLE_PIE
        bit<16> diff_to_old_queue_delay;
        bit<16> diff_to_target;
    #endif

    #ifdef EGRESS_DATAPLANE_PIE
        int<32> diff_to_old_queue_delay;
        int<32> diff_to_target;
    #endif


    bit<32> drop_probability;
    bit<32> random;

    bit<32> drop_probability_update;
    bit<1> drop_probability_increase;

    bit<16> alpha_range;
    bit<16> beta_range;

    bit<32> alpha_part;
    bit<32> beta_part;
    bit<32> beta_part_temp;
    bit<32> beta_alpha_ssubtraction;

    bit<1> alpha_positive;
    bit<1> beta_positive;
    bit<1> alpha_geq_beta;

    bool drop;
    bit<1> isPIEPacket;

}   

#endif


