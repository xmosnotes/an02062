// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "ncm_ntb.h"
#include "ncm_descriptors.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static unsigned get16(const unsigned char *data)
{
    return data[0] | (unsigned)data[1] << 8;
}

static void check_configuration(const unsigned char *config, unsigned size, unsigned packet)
{
    assert(size == 94 && get16(config + 2) == size);
    assert(config[4] == 2 && config[5] == 1);
    unsigned interfaces = 0, endpoints = 0, ncm = 0, iad = 0, ethernet = 0;
    unsigned current_interface = 0, alternate = 0, interface_endpoints = 0, expected_endpoints = 0;
    for (unsigned offset = 0; offset < size;) {
        const unsigned char *descriptor = config + offset;
        unsigned bytes = descriptor[0], type = descriptor[1];
        assert(bytes >= 2 && bytes <= size - offset);
        if (type == 11) {
            assert(bytes == 8 && descriptor[2] == 0 && descriptor[3] == 2);
            assert(descriptor[4] == 2 && descriptor[5] == 0x0d);
            iad++;
        } else if (type == 4) {
            assert(interface_endpoints == expected_endpoints);
            assert(bytes == 9);
            current_interface = descriptor[2];
            alternate = descriptor[3];
            interface_endpoints = 0;
            expected_endpoints = descriptor[4];
            if (!current_interface) {
                assert(!alternate && expected_endpoints == 1);
                assert(descriptor[5] == 2 && descriptor[6] == 0x0d);
            } else {
                assert(current_interface == 1 && alternate <= 1);
                assert(expected_endpoints == (alternate ? 2 : 0));
                assert(descriptor[5] == 0x0a && descriptor[7] == 1);
            }
            interfaces++;
        } else if (type == 5) {
            assert(bytes == 7);
            if (!current_interface) {
                assert(descriptor[2] == 0x81 && descriptor[3] == 3);
                assert(get16(descriptor + 4) == 16);
                assert(descriptor[6] == (packet == 512 ? 9 : 32));
            } else {
                assert(alternate == 1);
                assert(descriptor[2] == 0x01 || descriptor[2] == 0x82);
                assert(descriptor[3] == 2 && get16(descriptor + 4) == packet);
            }
            endpoints++;
            interface_endpoints++;
        } else if (type == 0x24 && descriptor[2] == 0x1a) {
            assert(bytes == 6 && get16(descriptor + 3) == 0x0100);
            assert(descriptor[5] == 0);
            ncm++;
        } else if (type == 0x24 && descriptor[2] == 0x0f) {
            assert(bytes == 13 && descriptor[3] == 3);
            assert(get16(descriptor + 8) == 1514);
            ethernet++;
        }
        offset += bytes;
    }
    assert(interface_endpoints == expected_endpoints);
    assert(iad == 1 && interfaces == 3 && endpoints == 3 && ncm == 1 && ethernet == 1);
}

int main(int argc, char *argv[])
{
    assert(sizeof(devDesc) == 18 && devDesc[0] == 18);
    assert(get16(devDesc + 2) == 0x0200);
    assert(devDesc[4] == 0xef && devDesc[5] == 2 && devDesc[6] == 1);
    assert(devDesc[7] == 64 && devDesc[17] == 1);
    if (argc != 2) {
        fputs("Specify fs or hs\n", stderr);
        return 2;
    }
    if (!strcmp(argv[1], "fs"))
        check_configuration(cfgDescFs, sizeof(cfgDescFs), 64);
    else if (!strcmp(argv[1], "hs"))
        check_configuration(cfgDescHs, sizeof(cfgDescHs), 512);
    else {
        fprintf(stderr, "Unknown descriptor test case: %s\n", argv[1]);
        return 2;
    }
    printf("PASS: %s\n", argv[1]);
    return 0;
}
