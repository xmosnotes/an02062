// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef NCM_DESCRIPTORS_H_
#define NCM_DESCRIPTORS_H_

/* Development identity only: obtain an assigned XMOS PID before publication.
 * Do not reuse AN00131's ECM PID; hosts cache class-driver associations. */
#ifndef NCM_VENDOR_ID
#define NCM_VENDOR_ID 0x20b1
#endif
#ifndef NCM_PRODUCT_ID
#define NCM_PRODUCT_ID 0x0000
#endif

#define LO(v) ((v) & 255)
#define HI(v) (((v) >> 8) & 255)

static unsigned char devDesc[] = {
    18, 1, 0x00, 0x02, 0xef, 0x02, 0x01, 64,
    LO(NCM_VENDOR_ID), HI(NCM_VENDOR_ID), LO(NCM_PRODUCT_ID), HI(NCM_PRODUCT_ID),
    0x00, 0x01, 1, 2, 0, 1
};

/* IAD, CDC-NCM control interface and data interface alternate settings.
 * Total: 9+8+9+5+5+13+6+7+9+9+7+7 = 94 bytes.
 * bmNetworkCapabilities=0: fixed MAC/MTU, NTB16 only, no optional CRC,
 * packet-filter programming or extended SET_NTB_INPUT_SIZE. */
#define NCM_CONFIGURATION(packet, interval) \
    9, 2, 94, 0, 2, 1, 0, 0x80, 200, \
    8, 11, 0, 2, 0x02, 0x0d, 0x00, 0, \
    9, 4, 0, 0, 1, 0x02, 0x0d, 0, 0, \
    5, 0x24, 0, 0x20, 0x01, \
    5, 0x24, 6, 0, 1, \
    13, 0x24, 0x0f, 3, 0, 0, 0, 0, LO(NCM_MAX_FRAME_SIZE), HI(NCM_MAX_FRAME_SIZE), 0, 0, 0, \
    6, 0x24, 0x1a, 0x00, 0x01, 0, \
    7, 5, 0x81, 3, 16, 0, interval, \
    9, 4, 1, 0, 0, 0x0a, 0, 1, 0, \
    9, 4, 1, 1, 2, 0x0a, 0, 1, 0, \
    7, 5, 0x01, 2, LO(packet), HI(packet), 0, \
    7, 5, 0x82, 2, LO(packet), HI(packet), 0

static unsigned char cfgDescFs[] = {NCM_CONFIGURATION(64, 32)};
static unsigned char cfgDescHs[] = {NCM_CONFIGURATION(512, 9)};

#ifdef __XC__
unsafe {
    static char * unsafe stringDescriptors[] = {
        "\x09\x04",
        "XMOS",
        "XMOS USB CDC-NCM Ethernet Device",
        "00229708A003"
    };
}
#endif
#endif
