/*
    PIE for Tofino
    Copyright (c) 2021 
	
	Author: Ike Kunze
	E-mail: kunze@comsys.rwth-aachen.de
*/

#include <core.p4>
#include <tna.p4>

#define DROPPING_ACTIVE
#define EGRESS_TABLE_PIE

#include "source-types.p4"
#include "source-egress-common-skeleton.p4"
#include "source-ingress-dataplane-table.p4"

Pipeline(
    IngressParser(),
    Ingress(),
    IngressDeparser(),
    EgressParser(),
    Egress(),
    EgressDeparser()
) pipe;

Switch(pipe) main;

