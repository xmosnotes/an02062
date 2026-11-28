// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "ncm_ntb.h"
#include <string.h>

unsigned ncm_get16(const unsigned char data[])
{
    return data[0] | ((unsigned)data[1] << 8);
}

unsigned ncm_get32(const unsigned char data[])
{
    return ncm_get16(data) | (ncm_get16(data + 2) << 16);
}

void ncm_put16(unsigned char data[], unsigned value)
{
    data[0] = value;
    data[1] = value >> 8;
}

void ncm_put32(unsigned char data[], unsigned value)
{
    ncm_put16(data, value);
    ncm_put16(data + 2, value >> 16);
}

static int overlap(unsigned a, unsigned alen, unsigned b, unsigned blen)
{
    return a < b + blen && b < a + alen;
}

int ncm_ntb_parse(const unsigned char data[], unsigned length,
                  ncm_datagram_t frames[])
{
    unsigned ndps[NCM_MAX_DATAGRAMS], sizes[NCM_MAX_DATAGRAMS];
    unsigned tables = 0, count = 0;
    if (length < 12 || length > NCM_NTB_MAX_SIZE ||
        ncm_get32(data) != 0x484d434e || ncm_get16(data + 4) != 12)
        return -1;
    unsigned block = ncm_get16(data + 8);
    /* A zero block length means that the USB transfer delineates the NTB.
     * Windows can append one zero byte to avoid a USB ZLP. */
    if (!block)
        block = length;
    if (block < 12 || block > length ||
        (length != block && !(length == block + 1 && data[block] == 0)))
        return -1;
    unsigned ndp = ncm_get16(data + 10);
    while (ndp) {
        if (tables == NCM_MAX_DATAGRAMS || ndp < 12 || (ndp & 3) ||
            ndp > block || block - ndp < 12)
            return -1;
        if (ncm_get32(data + ndp) != 0x304d434e)
            return -1;
        unsigned size = ncm_get16(data + ndp + 4);
        if (size < 12 || (size & 3) || size > block - ndp)
            return -1;
        for (unsigned i = 0; i < tables; ++i)
            if (overlap(ndp, size, ndps[i], sizes[i]))
                return -1;
        ndps[tables] = ndp;
        sizes[tables++] = size;
        int terminated = 0;
        for (unsigned entry = ndp + 8; entry < ndp + size; entry += 4) {
            unsigned offset = ncm_get16(data + entry);
            unsigned bytes = ncm_get16(data + entry + 2);
            if (!offset && !bytes) {
                terminated = 1;
                break;
            }
            /* Payload alignment is advertised to the host but not required:
             * frames are copied out, so any in-bounds offset is safe. */
            if (!offset || !bytes || offset < 12 ||
                bytes < 14 || bytes > NCM_MAX_FRAME_SIZE ||
                offset > block || bytes > block - offset ||
                count == NCM_MAX_DATAGRAMS)
                return -1;
            frames[count].offset = offset;
            frames[count++].length = bytes;
        }
        if (!terminated)
            return -1;
        ndp = ncm_get16(data + ndp + 6);
    }
    for (unsigned i = 0; i < count; ++i) {
        for (unsigned j = 0; j < tables; ++j)
            if (overlap(frames[i].offset, frames[i].length, ndps[j], sizes[j]))
                return -1;
        for (unsigned j = 0; j < i; ++j)
            if (overlap(frames[i].offset, frames[i].length,
                        frames[j].offset, frames[j].length))
                return -1;
    }
    return (int)count;
}

void ncm_ntb_init(unsigned char data[], unsigned sequence)
{
    memset(data, 0, NCM_TX_HEADER_SIZE);
    ncm_put32(data, 0x484d434e);       /* "NCMH" */
    ncm_put16(data + 4, 12);
    ncm_put16(data + 6, sequence);
    ncm_put16(data + 10, 12);
    ncm_put32(data + 12, 0x304d434e); /* "NCM0" */
}

unsigned ncm_ntb_append(unsigned char data[], unsigned used, unsigned count,
                        const unsigned char frame[], unsigned length, unsigned limit)
{
    if (used < NCM_TX_HEADER_SIZE || used > NCM_NTB_MAX_SIZE ||
        count >= NCM_TX_DATAGRAMS || length < 14 ||
        length > NCM_MAX_FRAME_SIZE || limit > NCM_NTB_MAX_SIZE)
        return 0;
    unsigned offset = NCM_FRAME_OFFSET(used);
    if (offset > limit || length > limit - offset)
        return 0;
    memset(data + used, 0, offset - used);
    memcpy(data + offset, frame, length);
    ncm_put16(data + 20 + 4 * count, offset);
    ncm_put16(data + 22 + 4 * count, length);
    return offset + length;
}

unsigned ncm_ntb_finish(unsigned char data[], unsigned used, unsigned count)
{
    if (!count || count > NCM_TX_DATAGRAMS ||
        used < NCM_TX_HEADER_SIZE || used > NCM_NTB_MAX_SIZE)
        return 0;
    ncm_put16(data + 8, used);
    ncm_put16(data + 16, 8 + 4 * (count + 1));
    return used;
}
