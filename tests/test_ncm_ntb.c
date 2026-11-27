// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "ncm_ntb.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned char ntb[NCM_NTB_MAX_SIZE + 1];
static unsigned char original[NCM_NTB_MAX_SIZE + 1];
static unsigned char frame[NCM_MAX_FRAME_SIZE];
static ncm_datagram_t frames[NCM_MAX_DATAGRAMS];

static unsigned build(unsigned bytes, unsigned count, unsigned limit)
{
    memset(ntb, 0xa5, sizeof(ntb));
    ncm_ntb_init(ntb, 65535);
    unsigned used = NCM_TX_HEADER_SIZE;
    for (unsigned i = 0; i < count; ++i) {
        used = ncm_ntb_append(ntb, used, i, frame, bytes, limit);
        assert(used);
    }
    return ncm_ntb_finish(ntb, used, count);
}

static void round_trips(void)
{
    const unsigned lengths[] = {14, 42, 60, 64, 424, 512, 1500, 1514};
    for (unsigned i = 0; i < sizeof(frame); ++i)
        frame[i] = (unsigned char)i;
    for (unsigned i = 0; i < sizeof(lengths) / sizeof(lengths[0]); ++i) {
        unsigned maximum = lengths[i] == 1514 || lengths[i] == 1500 ? 10 : 16;
        for (unsigned count = 1; count <= maximum; ++count) {
            unsigned length = build(lengths[i], count, NCM_NTB_MAX_SIZE);
            assert(ncm_get16(ntb + 6) == 65535);
            assert(ncm_ntb_parse(ntb, length, frames) == (int)count);
            for (unsigned j = 0; j < count; ++j) {
                assert((frames[j].offset + 14) % 4 == 0);
                assert(frames[j].length == lengths[i]);
                assert(!memcmp(ntb + frames[j].offset, frame, lengths[i]));
            }
        }
    }
    unsigned length = build(422, 1, 2048);
    assert(length == 512); /* A full last USB packet requires termination. */
    ntb[length] = 0;
    assert(ncm_ntb_parse(ntb, length + 1, frames) == 1); /* Windows pad */
    ntb[length] = 1;
    assert(ncm_ntb_parse(ntb, length + 1, frames) == -1);
    ncm_put16(ntb + 8, 0); /* USB transfer-delimited block */
    assert(ncm_ntb_parse(ntb, length, frames) == 1);
    length = build(1514, 1, 2048);
    assert(!ncm_ntb_append(ntb, length, 1, frame, 1514, 2048));
    assert(!ncm_ntb_append(ntb, length, 1, frame, 13, 2048));
    assert(!ncm_ntb_append(ntb, length, 16, frame, 60, 16384));
    assert(!ncm_ntb_append(ntb, length, 1, frame, 1515, 16384));
    assert(!ncm_ntb_finish(ntb, length, 0));
}

static void malformed(void)
{
    unsigned length = build(60, 2, NCM_NTB_MAX_SIZE);
    memcpy(original, ntb, sizeof(ntb));
    for (unsigned i = 0; i < length; ++i)
        assert(ncm_ntb_parse(ntb, i, frames) == -1);
    const unsigned offsets[] = {0, 4, 8, 10, 12, 16, 18, 20, 22, 24, 26};
    const unsigned values[] = {0xffff, 0, 0xffff, 13, 0xffff, 7, 12, 4, 1515, 0xffff, 0};
    for (unsigned i = 0; i < sizeof(offsets) / sizeof(offsets[0]); ++i) {
        memcpy(ntb, original, sizeof(ntb));
        ncm_put16(ntb + offsets[i], values[i]);
        assert(ncm_ntb_parse(ntb, length, frames) == -1);
    }
    memcpy(ntb, original, sizeof(ntb));
    ncm_put16(ntb + 24, ncm_get16(ntb + 20)); /* Overlapping frames */
    assert(ncm_ntb_parse(ntb, length, frames) == -1);
    memcpy(ntb, original, sizeof(ntb));
    ncm_put16(ntb + 20, 12); /* Datagram overlaps NDP */
    assert(ncm_ntb_parse(ntb, length, frames) == -1);
    memcpy(ntb, original, sizeof(ntb));
    unsigned misaligned = ncm_get16(ntb + 20) - 1; /* Host ignored payload alignment */
    ncm_put16(ntb + 20, misaligned);
    assert(ncm_ntb_parse(ntb, length, frames) == 2 && frames[0].offset == misaligned);
    assert(ncm_ntb_parse(ntb, NCM_NTB_MAX_SIZE + 1, frames) == -1);
}

static void chained_ndps(void)
{
    /* Two independently positioned NDPs, both after the frame payloads. */
    memset(ntb, 0, sizeof(ntb));
    ncm_put32(ntb, 0x484d434e);
    ncm_put16(ntb + 4, 12);
    ncm_put16(ntb + 8, 168);
    ncm_put16(ntb + 10, 136);
    memcpy(ntb + 14, frame, 60);
    memcpy(ntb + 74, frame, 60);
    for (unsigned ndp = 136; ndp <= 152; ndp += 16) {
        ncm_put32(ntb + ndp, 0x304d434e);
        ncm_put16(ntb + ndp + 4, 16);
        ncm_put16(ntb + ndp + 8, ndp == 136 ? 14 : 74);
        ncm_put16(ntb + ndp + 10, 60);
    }
    ncm_put16(ntb + 142, 152);
    assert(ncm_ntb_parse(ntb, 168, frames) == 2);
    ncm_put16(ntb + 158, 136); /* Cycle */
    assert(ncm_ntb_parse(ntb, 168, frames) == -1);
}

static void receive_datagram_limit(void)
{
    for (unsigned count = NCM_MAX_DATAGRAMS; count <= NCM_MAX_DATAGRAMS + 1; ++count) {
        memset(ntb, 0, sizeof(ntb));
        ncm_put32(ntb, 0x484d434e);
        ncm_put16(ntb + 4, 12);
        ncm_put16(ntb + 10, 12);
        ncm_put32(ntb + 12, 0x304d434e);
        ncm_put16(ntb + 16, 8 + 4 * (count + 1));
        unsigned used = 20 + 4 * (count + 1);
        for (unsigned i = 0; i < count; ++i) {
            unsigned offset = NCM_FRAME_OFFSET(used);
            ncm_put16(ntb + 20 + i * 4, offset);
            ncm_put16(ntb + 22 + i * 4, 60);
            memcpy(ntb + offset, frame, 60);
            used = offset + 60;
        }
        ncm_put16(ntb + 8, used);
        int result = ncm_ntb_parse(ntb, used, frames);
        assert(result == (count == NCM_MAX_DATAGRAMS ? NCM_MAX_DATAGRAMS : -1));
    }
}

static unsigned random_word(void)
{
    static unsigned state = 0x13102062;
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

static void mutation_tests(void)
{
    unsigned length = build(60, 4, NCM_NTB_MAX_SIZE);
    memcpy(original, ntb, sizeof(ntb));
    for (unsigned iteration = 0; iteration < 20000; ++iteration) {
        memcpy(ntb, original, sizeof(ntb));
        for (unsigned j = 0; j < 4; ++j)
            ntb[random_word() % length] = random_word();
        unsigned bytes = random_word() % (length + 2);
        int count = ncm_ntb_parse(ntb, bytes, frames);
        assert(count >= -1 && count <= NCM_MAX_DATAGRAMS);
        for (int j = 0; j < count; ++j) {
            assert(frames[j].offset <= bytes);
            assert(frames[j].length <= bytes - frames[j].offset);
        }
    }
}

int main(int argc, char *argv[])
{
    if (argc != 2) {
        fputs("Specify one NTB16 test case\n", stderr);
        return 2;
    }
    for (unsigned i = 0; i < sizeof(frame); ++i)
        frame[i] = (unsigned char)i;
    if (!strcmp(argv[1], "round_trips"))
        round_trips();
    else if (!strcmp(argv[1], "malformed"))
        malformed();
    else if (!strcmp(argv[1], "chained_ndps"))
        chained_ndps();
    else if (!strcmp(argv[1], "receive_datagram_limit"))
        receive_datagram_limit();
    else if (!strcmp(argv[1], "mutation_tests"))
        mutation_tests();
    else {
        fprintf(stderr, "Unknown NTB16 test case: %s\n", argv[1]);
        return 2;
    }
    printf("PASS: %s\n", argv[1]);
    return 0;
}
