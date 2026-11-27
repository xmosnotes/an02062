// Copyright 2015-2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/* Minimal demonstration IPv4 responder for this application note only. It is
 * not a general TCP/IP stack: there is no TCP retransmission, IP options,
 * fragmentation or IPv6. Use a maintained stack (e.g. lib_xtcp) in products. */

#include <xclib.h>
#include <print.h>
#include "femtoUDP.h"
#include "femtoIP.h"
#include "ethernet.h"

void patchUDPHeader(unsigned int packet[], int packetHighestByteIndex, int to, int srcPortRev, int destPortRev) {
    int packetLength = packetHighestByteIndex - 34;

    patchIPHeader(packet, packetLength + 20, to, 0);

    (packet, unsigned short[])[17] = srcPortRev;
    (packet, unsigned short[])[18] = destPortRev;
    (packet, unsigned short[])[19] = byterev(packetLength) >> 16;
    (packet, unsigned short[])[20] = 0; // checksum to be patched.

    onesChecksum(0x0011 + packetLength,
                 (packet, unsigned short[]), 13, (packetHighestByteIndex-1)>>1, 20);
}
