// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef NCM_NTB_H_
#define NCM_NTB_H_

/* Portable, allocation-free NCM 1.0 NTB16 framing. No Ethernet FCS or NCM CRC. */
#define NCM_NTB_MAX_SIZE 16384
#define NCM_MAX_DATAGRAMS 32
#define NCM_MAX_FRAME_SIZE 1514
#define NCM_TX_DATAGRAMS 16
#define NCM_TX_HEADER_SIZE (12 + 8 + 4 * (NCM_TX_DATAGRAMS + 1))
/* NCM divisor/remainder apply to the payload after the 14-byte Ethernet
 * header, not the beginning of the Ethernet frame. Remainder is zero. */
#define NCM_FRAME_OFFSET(used) ((((used) + 17u) & ~3u) - 14u)

typedef struct ncm_datagram {
    unsigned offset;
    unsigned length;
} ncm_datagram_t;

unsigned ncm_get16(const unsigned char data[]);
unsigned ncm_get32(const unsigned char data[]);
void ncm_put16(unsigned char data[], unsigned value);
void ncm_put32(unsigned char data[], unsigned value);

/* Returns -1 for invalid input, otherwise the number of Ethernet datagrams.
 * Validates the whole block before exposing any datagram to the application.
 * Traversal and output are bounded, including chained NDPs and cyclic input. */
int ncm_ntb_parse(const unsigned char data[], unsigned length,
                  ncm_datagram_t frames[]);

/* The builder reserves a fixed NDP area and zeroes all padding. Append returns
 * zero if the frame or negotiated NTB limit cannot be accommodated. */
void ncm_ntb_init(unsigned char data[], unsigned sequence);
unsigned ncm_ntb_append(unsigned char data[], unsigned used, unsigned count,
                        const unsigned char frame[], unsigned length, unsigned limit);
unsigned ncm_ntb_finish(unsigned char data[], unsigned used, unsigned count);

#endif
