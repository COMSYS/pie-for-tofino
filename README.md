# Tofino + P4: A Strong Compound for AQM on High-Speed Networks?

This repository contains the data plane and control plane implementations of our three variants of PIE for Tofino in P4<sub>16</sub>.
Note: The code has been tested with SDE-9.1.0.

## Publication

* Ike Kunze, Moritz Gunz, David Saam, Klaus Wehrle and Jan Rüth: *Tofino + P4: A Strong Compound for AQM on High-Speed Networks?*. In Proceedings of the International Symposium on Integrated Network Management (IM '21), IFIP/IEEE, 2021.

If you use any portion of our work, please consider citing our publication.

```
@Inproceedings {2021-kunze-aqm-tofino-p4,
   author = {Kunze, Ike and Gunz, Moritz and Saam, David and Wehrle, Klaus and R{\"u}th, Jan},
   title = {Tofino + P4: A Strong Compound for AQM on High-Speed Networks?},
   booktitle = {Proceedings of the International Symposium on Integrated Network Management (IM '21)},
   year = {2021},
   month = {May},
   publisher = {IFIP/IEEE},
   doi = {XX.XXXX/XXX}
}
```


## Content


### P4_16 Implementation

The P4_16 source code for our three PIE variants (PIE<sub>CP</sub>, PIE<sub>DP</sub>, and PIE<sub>TABLE</sub>) is located in ``p4src``.
On a high-level, the variants are captured in the corresponding files ``pie_(controlplane|dataplane|table.p4)``.

Our implementation is structured to reuse as much code as possible across the different variants.
This works in parts for PIE<sub>DP</sub> and PIE<sub>TABLE</sub> while PIE<sub>CP</sub> largely has an independent implementation.
The actual logic of our implementations is contained in the ``source-*.p4`` files. 

File | Pipeline Part | Purpose
--- | --- | ---
``source-types.p4`` | - | collects general type definitions (headers, etc.)
``source-ingress-dataplane-table.p4`` | Ingress | Ingress logic for PIE<sub>DP</sub> and PIE<sub>TABLE</sub>
``source-ingress-controlplane.p4`` | Ingress | Ingress logic for PIE<sub>CP</sub>
``source-egress-common-skeleton.p4`` | Egress | Common egress logic for PIE<sub>DP</sub> and PIE<sub>TABLE</sub>. <br> PIE<sub>DP</sub> /PIE<sub>TABLE</sub> fill out specific parts of the code.
``source-egress-dataplane.p4`` | Egress | Specific egress logic for PIE<sub>DP</sub> 
``source-egress-table.p4`` | Egress | Specific egress logic for PIE<sub>TABLE</sub>
``source-egress-controlplane`` | Egress | Egress logic for PIE<sub>CP</sub>


### Support scripts/files

File | Purpose
--- | ---
``run_pd_rpc/configure_pktgen_sampling_flow.py`` | Configure PIE sampling flow on the pktgen.
``bfrt_python/pie_table_fill.py`` | Script that fills the compute_drop_probability_update table on the fly
``utilities/pie_generate_tables.py`` | Script to precompute alpha_range and beta_range tables for static inclusion.
``bfrt_cpp/run_controlplane_pie.cpp`` | Control plane implementation for PIE<sub>CP</sub>

## License
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.