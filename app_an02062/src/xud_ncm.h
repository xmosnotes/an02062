// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef XUD_NCM_H_
#define XUD_NCM_H_

#include <xccompat.h>
#include "xud.h"
#include "ncm_ntb.h"

interface usb_cdc_ncm_if {
    int is_frame_available();
    [[guarded]] void read_frame(unsigned char buf[], unsigned &length);
    [[guarded]] void send_frame(unsigned char buf[], unsigned &length);
};

/* Endpoint task owns all transport state; EP0 never shares mutable globals. */
interface ncm_control_if {
    void set_link(unsigned configured, unsigned alternate);
    unsigned set_input_size(unsigned size);
};

void Endpoint0(chanend c_out, chanend c_in, client interface ncm_control_if control);
void CdcNcmEndpointsHandler(chanend c_notify, chanend c_out, chanend c_in,
                            server interface usb_cdc_ncm_if ncm,
                            server interface ncm_control_if control);

#endif
