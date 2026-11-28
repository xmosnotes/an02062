// Copyright 2015-2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

/* Minimal demonstration IPv4 responder for this application note only. It is
 * not a general TCP/IP stack: there is no TCP retransmission, IP options,
 * fragmentation or IPv6. Use a maintained stack (e.g. lib_xtcp) in products. */

#include <xclib.h>
#include <print.h>
#include <stdio.h>
#include <assert.h>
#include "packet_buffer.h"
#include "ethernet.h"
#include "femtoIP.h"
#include "femtoUDP.h"
#include "femtoTCP.h"
#include "dhcp.h"
#include "gpio.h"

/* IP Addresses of the USB device (Server) and the Host PC (Client) */
int ipAddressServer   = 0xA9FE5555;
int ipAddressClient = 0xA9FEAAAA;
/* Returns byte n (0 = most significant) of an IPv4 address. The addresses
 * can change at run time, so they have a single integer representation. */
static unsigned ipByte(int ip, int n) {
    return ((unsigned)ip >> (24 - 8 * n)) & 0xff;
}

/* MAC Addresses of the USB device and the Host PC */
const char macAddressServer[6] = {0x00, 0x22, 0x97, 0x08, 0xA0, 0x02};
const char macAddressClient[6] = {0x00, 0x22, 0x97, 0x08, 0xA0, 0x03};

/* Server name as found in the DNS query */
unsigned char localName[] = "\x08xmos-ncm\x05local";

struct packet_stats_t stats;

void initPacketStats()
{
    stats.total_tx_packets = 0;
    stats.total_rx_packets = 0;
    stats.arp_rx_packets = 0;
    stats.tcp_rx_packets = 0;
    stats.udp_rx_packets = 0;
    stats.icmp_rx_packets = 0;
    stats.total_rx_bytes = 0;
    stats.total_tx_bytes = 0;
}

void getMacAddressString(unsigned char * unsafe addr) {
    unsafe {
    for(int i = 0; i < 6; i++) {
        sprintf(addr + (2*i), "%.2x", macAddressClient[i]);
    }
    }
}

void onesChecksum(unsigned int sum, unsigned short data[], int begin, int end, int to) {
    for(int i = begin; i <= end; i++) {
        sum += byterev(data[i]) >> 16;
    }
    sum = (sum & 0xffff) + (sum >> 16);
    sum = (sum & 0xffff) + (sum >> 16);
    data[to] = byterev((~sum) & 0xffff) >> 16;
}

static int makeGratuitousArp(unsigned int packet[]) {
    packet[0] = 0xffffffff;
    packet[1] = 0xffffffff;
    packet[3] = 0x01000608;
    packet[4] = 0x04060008;
    packet[5] = 0x00000100;
    packet[7] = byterev(ipAddressServer);
    packet[8] = 0;
    packet[9] = ((unsigned)byterev(ipAddressServer)) << 16;
    packet[10] = ((unsigned)byterev(ipAddressServer)) >> 16;
    for(int i = 0; i < 6; i++) {
        (packet, char[])[ 6+i] = macAddressServer[i];
        (packet, char[])[22+i] = macAddressServer[i];
    }
    return 42;
}

static int makeOrdinaryArp(unsigned int packet[]) {
    packet[0] = 0xffffffff;
    packet[1] = 0xffffffff;
    packet[3] = 0x01000608;
    packet[4] = 0x04060008;
    packet[5] = 0x00000200;
    packet[7] = byterev(ipAddressServer);
    packet[8] = 0;
    packet[9] = ((unsigned)byterev(ipAddressClient)) << 16;
    packet[10] = ((unsigned)byterev(ipAddressClient)) >> 16;
    for(int i = 0; i < 6; i++) {
        (packet, char[])[ 6+i] = macAddressServer[i];
        (packet, char[])[22+i] = macAddressServer[i];
    }
    return 42;
}

static int makeICMPReply(unsigned int rxbuf[], unsigned int txbuf[]) {
    unsigned icmp_checksum;
    int datalen;
    int totallen;
    const int ttl = 0x40;
    int pad;

    // Precomputed empty IP header checksum (inverted, bytereversed and shifted right)
    unsigned ip_checksum = 0x0185;

    for (int i = 0; i < 6; i++)
    {
        (txbuf, unsigned char[])[i] = (rxbuf, unsigned char[])[6 + i];
    }
    for (int i = 0; i < 4; i++)
    {
        (txbuf, unsigned char[])[30 + i] = (rxbuf, unsigned char[])[26 + i];
    }
    icmp_checksum = byterev((rxbuf, const unsigned[])[9]) >> 16;
    for (int i = 0; i < 4; i++)
    {
        (txbuf, unsigned char[])[38 + i] = (rxbuf, unsigned char[])[38 + i];
    }
    totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
    datalen = totallen - 28;

    for (int i = 0; i < datalen; i++)
    {
          (txbuf, unsigned char[])[42 + i] = (rxbuf, unsigned char[])[42+i];
    }

    for (int i = 0; i < 6; i++)
    {
      (txbuf, unsigned char[])[6 + i] = macAddressServer[i];
    }
    (txbuf, unsigned[])[3] = 0x00450008;
    totallen = byterev(28 + datalen) >> 16;
    (txbuf, unsigned[])[4] = totallen;
    ip_checksum += totallen;
    (txbuf, unsigned[])[5] = 0x01000000 | (ttl << 16);
    (txbuf, unsigned[])[6] = 0;
    for (int i = 0; i < 4; i++)
    {
      (txbuf, unsigned char[])[26 + i] = ipByte(ipAddressServer, i);
    }
    ip_checksum += (ipByte(ipAddressServer, 0) | ipByte(ipAddressServer, 1) << 8);
    ip_checksum += (ipByte(ipAddressServer, 2) | ipByte(ipAddressServer, 3) << 8);
    ip_checksum += (txbuf, unsigned char[])[30] | ((txbuf, unsigned char[])[31] << 8);
    ip_checksum += (txbuf, unsigned char[])[32] | ((txbuf, unsigned char[])[33] << 8);

    (txbuf, unsigned char[])[34] = 0x00;
    (txbuf, unsigned char[])[35] = 0x00;

    icmp_checksum = (icmp_checksum + 0x0800);
    icmp_checksum += icmp_checksum >> 16;
    (txbuf, unsigned char[])[36] = icmp_checksum >> 8;
    (txbuf, unsigned char[])[37] = icmp_checksum & 0xFF;

    while (ip_checksum >> 16)
    {
      ip_checksum = (ip_checksum & 0xFFFF) + (ip_checksum >> 16);
    }
    ip_checksum = byterev(~ip_checksum) >> 16;
    (txbuf, unsigned char[])[24] = ip_checksum >> 8;
    (txbuf, unsigned char[])[25] = ip_checksum & 0xFF;

    for (pad = 42 + datalen; pad < 64; pad++)
    {
      (txbuf, unsigned char[])[pad] = 0x00;
    }
    return pad;
}

/* DNS message offset of the DNS header in an Ethernet frame, used by name compression pointers */
#define DNS_HEADER_OFFSET 42

/* Returns the index just after the DNS name starting at index i */
static int dnsSkipName(unsigned char pkt[], unsigned len, int i) {
    while (i < len) {
        unsigned c = pkt[i];
        if (c == 0) {
            return i + 1;               /* End of name */
        }
        if ((c & 0xC0) == 0xC0) {
            return i + 2;               /* Compression pointer ends the name */
        }
        i += c + 1;                     /* Skip label */
    }
    return len;
}

/* Returns 1 if the DNS name starting at index i is our local name. Names in
 * questions after the first are usually compressed, i.e. they contain a pointer
 * back to an earlier name in the message */
static int dnsNameIsLocal(unsigned char pkt[], unsigned len, int i) {
    int j = 0;
    int jumps = 0;
    while (i < len && j < sizeof(localName)) {
        unsigned c = pkt[i];
        if ((c & 0xC0) == 0xC0) {
            if (++jumps > 4 || (i + 1) >= len) {
                return 0;
            }
            i = DNS_HEADER_OFFSET + (((c & 0x3F) << 8) | pkt[i + 1]);
            continue;
        }
        if (c >= 'A' && c <= 'Z') {
            c += 'a' - 'A';             /* Names are case insensitive */
        }
        if (c != localName[j]) {
            return 0;
        }
        if (c == 0) {
            return 1;                   /* Matched up to and including the end of name */
        }
        i++;
        j++;
    }
    return 0;
}

static int makeMDNSResponse(unsigned int packet[]) {
    int k;
    packet[10] = 0x00000000;
    packet[11] = 0x00000084;
    packet[12] = 0x00000100;
    packet[13] = 0x00000100;
    k = 54;
    for(int i = 0; i < sizeof(localName); i++) {
        (packet, char[])[k++] = localName[i];
    }
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 1;
    (packet, char[])[k++] = 0x80;
    (packet, char[])[k++] = 1;
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 255; // TTL2
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 4;
    (packet, char[])[k++] = ipAddressServer >> 24;
    (packet, char[])[k++] = ipAddressServer >> 16;
    (packet, char[])[k++] = ipAddressServer >> 8;
    (packet, char[])[k++] = ipAddressServer >> 0;


    for(int i = 0; i < sizeof(localName); i++) {
        (packet, char[])[k++] = localName[i];
    }
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 47;
    (packet, char[])[k++] = 0x80;
    (packet, char[])[k++] = 1;
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 255; // TTL2
    (packet, char[])[k++] = 0; // data length
    (packet, char[])[k++] = 10; // data length
    (packet, char[])[k++] = 5;
    (packet, char[])[k++] = 'l';
    (packet, char[])[k++] = 'o';
    (packet, char[])[k++] = 'c';
    (packet, char[])[k++] = 'a';
    (packet, char[])[k++] = 'l';
    (packet, char[])[k++] = 0; // Domain name end
    (packet, char[])[k++] = 0;
    (packet, char[])[k++] = 1;
    (packet, char[])[k++] = 0x40;


    (packet, char[])[k] = 0x00;

    patchUDPHeader(packet, k, 0xe00000fb, 0xe914, 0xe914);
    return k;
}


/* Send our mDNS response, the A record for our local name. Used both to answer
 * queries and to announce the name unprompted */
static void sendMDNSResponse(client interface usb_cdc_ncm_if cdc_ncm, unsigned int tx_buf[])
{
    unsigned len = makeMDNSResponse(tx_buf);
    cdc_ncm.send_frame((tx_buf, unsigned char[]), len);
    stats.total_tx_packets++;
    stats.total_tx_bytes += len;
}

/* Task to handle Ethernet frames received from USB endpoints */
void EthernetFrameHandler(client interface usb_cdc_ncm_if cdc_ncm)
{
    unsigned int rx_buf[MAX_FRAME_SIZE/sizeof(int)];
    unsigned rx_len;

    unsigned int tx_buf[MAX_FRAME_SIZE/sizeof(int)];
    unsigned tx_len;

    /* Start with all LEDs off, they are controlled from the web page */
    ledsSet(0);

    printstrln("--XMOS USB CDC-NCM Class demo--");
    printstr("\nServer IP Address: ");
    for(int i = 0; i < 4; i++) {
        printint(ipByte(ipAddressServer, i));
        if(i != 3) printchar('.');
    }
    printstrln("");
    printstrln("Server URL: http://xmos-ncm.local");
    while(1) {
        /* Blocking wait call to read a received ethernet frame */
        cdc_ncm.read_frame((rx_buf, unsigned char[]), rx_len);
        tx_len = 0;
        if (rx_len < 14)
            continue;
        stats.total_rx_packets++;
        stats.total_rx_bytes += rx_len;

        /* Get packet type */
        int type = (rx_buf, short[])[6];

        if (type == 0x0608) { // ARP packet
            if (rx_len < 42)
                continue;
            stats.arp_rx_packets++;
            if ((rx_buf, short[])[14] == (rx_buf, short[])[19] &&
                (rx_buf, short[])[15] == (rx_buf, short[])[20]) {

                int ip = byterev((rx_buf, unsigned int[])[7]);
                if (ip != ipAddressClient) {     // They missed DHCP and fell back to link local
                    ipAddressClient = ip;
                    if (ip == ipAddressServer) {   // Bum - they grabbed our address.
                        ipAddressServer = ip+1;
                    }
                }

                tx_len = makeGratuitousArp((tx_buf, unsigned int[]));
                cdc_ncm.send_frame((tx_buf, unsigned char[]), tx_len);
                stats.total_tx_packets++;
                stats.total_tx_bytes += tx_len;
                tx_len = 0;

                /* The host has just announced its address, announce our name so it is
                 * cached without the host having to ask (RFC 6762 section 8.3) */
                sendMDNSResponse(cdc_ncm, tx_buf);
                continue;
            }
            if ((rx_buf, short[])[20] == -1 ||
                (rx_buf, short[])[20] == (byterev(ipAddressServer)>>16) ) {
                tx_len = makeOrdinaryArp((tx_buf, unsigned int[]));
                cdc_ncm.send_frame((tx_buf, unsigned char[]), tx_len);
                stats.total_tx_packets++;
                stats.total_tx_bytes += tx_len;
                tx_len = 0;
            }

        } else if (type == 0x0008) { // IP packet
            /* The demonstration stack handles unfragmented IPv4 with a fixed
             * 20-byte IP header. Reject other layouts before fixed offsets. */
            if (rx_len < 34 || (rx_buf, unsigned char[])[14] != 0x45)
                continue;
            unsigned ip_len = ((unsigned)(rx_buf, unsigned char[])[16] << 8) |
                               (rx_buf, unsigned char[])[17];
            unsigned fragment = ((unsigned)(rx_buf, unsigned char[])[20] << 8) |
                                 (rx_buf, unsigned char[])[21];
            if (ip_len < 20 || ip_len > rx_len - 14 || (fragment & 0x3fff))
                continue;
            rx_len = ip_len + 14;
            int protocol = (rx_buf, unsigned char[])[23];

            if (protocol == 0x11) { // UDP
                if (rx_len < 42)
                    continue;
                unsigned udp_len = ((unsigned)(rx_buf, unsigned char[])[38] << 8) |
                                    (rx_buf, unsigned char[])[39];
                if (udp_len < 8 || udp_len > rx_len - 34)
                    continue;
                rx_len = udp_len + 34;
                stats.udp_rx_packets++;
                int destPort = (rx_buf, unsigned short[])[18];
                int srcPort = (rx_buf, unsigned short[])[17];
                if (destPort == 0x4300 && srcPort == 0x4400) {          // DHCP
                    /* Handle DHCP request from Host */
                    processDHCPPacket(rx_buf, rx_len, tx_buf, tx_len);
                    if(tx_len) {
                        cdc_ncm.send_frame((tx_buf, unsigned char[]), tx_len);
                        stats.total_tx_packets++;
                        stats.total_tx_bytes += tx_len;
                        tx_len = 0;

                        /* Announce our name as the host is configuring its address */
                        sendMDNSResponse(cdc_ncm, tx_buf);
                        continue;
                    }

                } else if (destPort == 0xe914 && srcPort == 0xe914) {   // MDNS
                    if (rx_len < 54)
                        continue;
                    /* Handle DNS query from Host */
                    int flags = (rx_buf, short[])[22];
                    int queries = byterev((rx_buf, short[])[23]) >> 16;
                    int index = 54;     /* First question, after the 12 byte DNS header */
                    int askedForUs = 0;
                    if (flags == 0) {   /* Standard query */
                        /* Look through all the questions for our name. The question type
                         * and class are not checked: hosts often ask for other record
                         * types (e.g. AAAA) and may set the "unicast response" bit in the
                         * class. The response holds our A record plus an NSEC record
                         * stating that no other record types exist, which the host caches
                         * whichever type it asked for */
                        for(int i = 0; i < queries && index < rx_len; i++) {
                            if (dnsNameIsLocal((rx_buf, unsigned char[]), rx_len, index)) {
                                askedForUs = 1;
                            }
                            /* Skip the name, QTYPE and QCLASS */
                            index = dnsSkipName((rx_buf, unsigned char[]), rx_len, index) + 4;
                        }
                    }
                    if (askedForUs) {
                        sendMDNSResponse(cdc_ncm, tx_buf);
                    }
                }
            } else if (protocol == 0x6) { // TCP
                stats.tcp_rx_packets++;
                processTCPPacket(rx_buf, rx_len, tx_buf, tx_len);
                if(tx_len) {
                    cdc_ncm.send_frame((tx_buf, unsigned char[]), tx_len);
                    stats.total_tx_packets++;
                    stats.total_tx_bytes += tx_len;
                    tx_len = 0;
                }
            } else if (protocol == 0x01) { // ICMP packet
                if (rx_len < 42)
                    continue;
                stats.icmp_rx_packets++;
                if(((rx_buf, unsigned int[])[3] == 0x00450008) &&
                        (((rx_buf, unsigned int[])[8] >> 16) == (0x0008))){

                    /* Check if the IP address is ours */
                    unsigned int ip = (((unsigned int)(rx_buf, unsigned short[])[16]) << 16) | (rx_buf, unsigned short[])[15];
                    if(byterev(ip) == ipAddressServer) {
                        tx_len = makeICMPReply(rx_buf, tx_buf);
                        cdc_ncm.send_frame((tx_buf, unsigned char[]), tx_len);
                        stats.total_tx_packets++;
                        stats.total_tx_bytes += tx_len;
                        tx_len = 0;
                    }
                }
            }
        }
    }
}
