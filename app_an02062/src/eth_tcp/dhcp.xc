// Copyright 2015-2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/* Minimal demonstration IPv4 responder for this application note only. It is
 * not a general TCP/IP stack: there is no TCP retransmission, IP options,
 * fragmentation or IPv6. Use a maintained stack (e.g. lib_xtcp) in products. */

#include <xclib.h>
#include <print.h>
#include "packet_buffer.h"
#include "ethernet.h"
#include "femtoIP.h"
#include "femtoUDP.h"
#include "femtoTCP.h"
#include "dhcp.h"

#define OPTION_START  282

static void wordCopy(unsigned int to[], unsigned int from[], int nWords) {
    for(int i = 0; i < nWords; i++) {
        to[i] = from[i];
    }
}

void processDHCPPacket(unsigned int packet[], unsigned len, unsigned int rsp_packet[], unsigned &rsp_len) {
    int index = OPTION_START;
    int request = -1;
    rsp_len = 0;
    if (len < OPTION_START)
        return;
    while (index < len) {
        int option = (packet, unsigned char[])[index];
        if (option == 53) {
            if (index + 2 >= len || (packet, unsigned char[])[index + 1] != 1)
                return;
            request = (packet, unsigned char[])[index+2];
            break;
        }
        if (option == 255) {
            break;
        }
        if (option == 0) {
            index++;
        } else {
            if (index + 1 >= len)
                return;
            unsigned option_len = (packet, unsigned char[])[index + 1];
            if (option_len > len - index - 2)
                return;
            index += 2 + option_len;
        }
    }
    if (request == 1 || request == 3) { // DISCOVER or REQUEST
        int k;

        wordCopy(rsp_packet, packet, OPTION_START/4);
        (rsp_packet, unsigned char[])[280] = (packet, unsigned char[])[280];
        (rsp_packet, unsigned char[])[281] = (packet, unsigned char[])[281];

        (rsp_packet, unsigned short[])[25] = 0;

        (rsp_packet, unsigned short[])[30] = byterev(ipAddressClient)>>16;
        (rsp_packet, unsigned short[])[29] = byterev(ipAddressClient);
        (rsp_packet, unsigned short[])[32] = byterev(ipAddressServer)>>16;
        (rsp_packet, unsigned short[])[31] = byterev(ipAddressServer);
        (rsp_packet, unsigned char[])[42] = 2;

        k = OPTION_START;
        (rsp_packet, unsigned char[])[k++] = 53;
        (rsp_packet, unsigned char[])[k++] = 1;
        (rsp_packet, unsigned char[])[k++] = request == 1 ? 2 : 5; // OFFER or ACK

        (rsp_packet, unsigned char[])[k++] = 51;
        (rsp_packet, unsigned char[])[k++] = 4;
        (rsp_packet, unsigned char[])[k++] = 0;
        (rsp_packet, unsigned char[])[k++] = 0;
        (rsp_packet, unsigned char[])[k++] = 1;
        (rsp_packet, unsigned char[])[k++] = 0;

        (rsp_packet, unsigned char[])[k++] = 54;
        (rsp_packet, unsigned char[])[k++] = 4;
        (rsp_packet, unsigned char[])[k++] = ipAddressServer >> 24;
        (rsp_packet, unsigned char[])[k++] = ipAddressServer >> 16;
        (rsp_packet, unsigned char[])[k++] = ipAddressServer >> 8;
        (rsp_packet, unsigned char[])[k++] = ipAddressServer >> 0;

        (rsp_packet, unsigned char[])[k++] = 1;
        (rsp_packet, unsigned char[])[k++] = 4;
        (rsp_packet, unsigned char[])[k++] = 255;
        (rsp_packet, unsigned char[])[k++] = 255;
        (rsp_packet, unsigned char[])[k++] = 0;
        (rsp_packet, unsigned char[])[k++] = 0;

        (rsp_packet, unsigned char[])[k++] = 255;
        (rsp_packet, unsigned char[])[k] = 0;

        patchUDPHeader(rsp_packet, k, 0xffffffff, 0x4300, 0x4400);
        rsp_len = k;
    }
}
