"""
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
"""

from ptf.testutils import *
import binascii

pktgen.enable(68) 

cfg = pktgen.app_cfg_init()

desired_packet_length = 70
cfg.length = desired_packet_length-6
cfg.timer =   117000
cfg.trigger_type = pktgen.TriggerType_t.TIMER_PERIODIC

pkt = simple_udp_packet(pktlen=desired_packet_length,
                        eth_dst='00:15:4d:13:82:b7',
                        eth_src='00:06:07:08:09:0a',
                        dl_vlan_enable=False,
                        vlan_vid=0,
                        vlan_pcp=0,
                        dl_vlan_cfi=0,
                        ip_src='10.0.0.10',
                        ip_dst='10.0.1.1',
                        ip_tos=0,
                        ip_ecn=None,
                        ip_dscp=None,
                        ip_ttl=64,
                        udp_sport=1234,
                        udp_dport=8765,
                        ip_ihl=None,
                        ip_options=False,
                        ip_flag=0,
                        ip_id=1,
                        with_udp_chksum=True,
                        udp_payload=binascii.unhexlify(
                            '2323' + '0000' * 13)
                        )         

pktgen.write_pkt_buffer(0, 1500, str(pkt)[6:])
pktgen.cfg_app(0, cfg)
pktgen.app_enable(0)
