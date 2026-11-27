// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include "xud_device.h"
#include "xud_ncm.h"
#include "ncm_descriptors.h"

#define GET_NTB_PARAMETERS 0x80
#define GET_NTB_FORMAT     0x83
#define SET_NTB_FORMAT     0x84
#define GET_NTB_INPUT_SIZE 0x85
#define SET_NTB_INPUT_SIZE 0x86
#define GET_CRC_MODE       0x89
#define SET_CRC_MODE       0x8a

static XUD_Result_t class_request(XUD_ep ep_out, XUD_ep ep_in,
                                  USB_SetupPacket_t sp, unsigned type,
                                  unsigned alternate, unsigned &input_size,
                                  client interface ncm_control_if control)
{
    unsigned data_words[18] = {0}; /* One EP0 OUT packet plus CRC/word slack. */
    unsigned char data[64];
    unsigned length;
    if (sp.wIndex != 0)
        return XUD_RES_ERR;
    if (type == USB_BMREQ_D2H_CLASS_INT && sp.wValue == 0) {
        switch (sp.bRequest) {
        case GET_NTB_PARAMETERS:
            if (!sp.wLength)
                return XUD_RES_ERR;
            ncm_put16(data, 28);
            ncm_put16(data + 2, 1); /* NTB16 only */
            ncm_put32(data + 4, NCM_NTB_MAX_SIZE);
            ncm_put16(data + 8, 4);
            ncm_put16(data + 10, 0);
            ncm_put16(data + 12, 4);
            ncm_put16(data + 14, 0); /* reserved */
            ncm_put32(data + 16, NCM_NTB_MAX_SIZE);
            ncm_put16(data + 20, 4);
            ncm_put16(data + 22, 0);
            ncm_put16(data + 24, 4);
            ncm_put16(data + 26, NCM_MAX_DATAGRAMS);
            return XUD_DoGetRequest(ep_out, ep_in, data, 28, sp.wLength);
        case GET_NTB_INPUT_SIZE:
            if (sp.wLength != 4)
                return XUD_RES_ERR;
            ncm_put32(data, input_size);
            return XUD_DoGetRequest(ep_out, ep_in, data, 4, sp.wLength);
        case GET_NTB_FORMAT:
        case GET_CRC_MODE:
            if (sp.wLength != 2)
                return XUD_RES_ERR;
            ncm_put16(data, 0);
            return XUD_DoGetRequest(ep_out, ep_in, data, 2, sp.wLength);
        }
    } else if (type == USB_BMREQ_H2D_CLASS_INT) {
        switch (sp.bRequest) {
        case SET_NTB_INPUT_SIZE: {
            if (sp.wValue || sp.wLength != 4)
                return XUD_RES_ERR;
            XUD_Result_t result = XUD_GetBuffer(ep_out, (data_words, unsigned char[]), length);
            if (result != XUD_RES_OKAY)
                return result;
            if (length != 4)
                return XUD_RES_ERR;
            unsigned size = ncm_get32((data_words, unsigned char[]));
            if (!control.set_input_size(size))
                return XUD_RES_ERR;
            input_size = size;
            return XUD_DoSetRequestStatus(ep_in);
        }
        case SET_NTB_FORMAT:
        case SET_CRC_MODE:
            if (sp.wValue || sp.wLength || alternate)
                return XUD_RES_ERR;
            return XUD_DoSetRequestStatus(ep_in);
        case 0x43: /* SET_ETHERNET_PACKET_FILTER: no filtering advertised. */
            if (sp.wLength || (sp.wValue & ~0x1f))
                return XUD_RES_ERR;
            return XUD_DoSetRequestStatus(ep_in);
        }
    }
    return XUD_RES_ERR;
}

void Endpoint0(chanend c_out, chanend c_in, client interface ncm_control_if control)
{
    XUD_ep ep_out = XUD_InitEp(c_out);
    XUD_ep ep_in = XUD_InitEp(c_in);
    XUD_BusSpeed_t speed = XUD_SPEED_HS;
    unsigned configured = 0, alternate = 0, input_size = NCM_NTB_MAX_SIZE;
    while (1) {
        USB_SetupPacket_t sp;
        XUD_Result_t result = USB_GetSetupPacket(ep_out, ep_in, sp);
        if (result == XUD_RES_OKAY) {
            unsigned type = (sp.bmRequestType.Direction << 7) |
                            (sp.bmRequestType.Type << 5) | sp.bmRequestType.Recipient;
            int handled = 0;
            if (type == USB_BMREQ_D2H_CLASS_INT || type == USB_BMREQ_H2D_CLASS_INT) {
                result = configured ? class_request(ep_out, ep_in, sp, type,
                                          alternate, input_size, control) : XUD_RES_ERR;
                handled = 1;
            } else if (type == USB_BMREQ_H2D_STANDARD_INT && sp.bRequest == USB_SET_INTERFACE) {
                handled = 1;
                result = XUD_RES_ERR;
                if (configured && sp.wLength == 0 &&
                    ((sp.wIndex == 0 && sp.wValue == 0) ||
                     (sp.wIndex == 1 && sp.wValue <= 1))) {
                    if (sp.wIndex == 1) {
                        alternate = sp.wValue;
                        XUD_ResetEpStateByAddr(0x01);
                        XUD_ResetEpStateByAddr(0x82);
                        control.set_link(configured, alternate);
                    }
                    result = XUD_DoSetRequestStatus(ep_in);
                }
            } else if (type == USB_BMREQ_D2H_STANDARD_INT && sp.bRequest == USB_GET_INTERFACE) {
                handled = 1;
                result = XUD_RES_ERR;
                if (configured && sp.wIndex <= 1 && !sp.wValue && sp.wLength == 1) {
                    unsigned char value[1] = {sp.wIndex == 1 ? alternate : 0};
                    result = XUD_DoGetRequest(ep_out, ep_in, value, 1, sp.wLength);
                }
            } else if (type == USB_BMREQ_H2D_STANDARD_DEV && sp.bRequest == USB_SET_CONFIGURATION) {
                handled = 1;
                result = XUD_RES_ERR;
                if (!sp.wIndex && !sp.wLength && sp.wValue <= 1) {
                    configured = sp.wValue;
                    alternate = 0;
                    input_size = NCM_NTB_MAX_SIZE;
                    control.set_link(configured, alternate);
                    control.set_input_size(input_size);
                    unsafe {
                        result = USB_StandardRequests(ep_out, ep_in, devDesc, sizeof(devDesc),
                            cfgDescHs, sizeof(cfgDescHs), null, 0, cfgDescFs, sizeof(cfgDescFs),
                            stringDescriptors, 4, sp, speed);
                    }
                }
            }
            if (!handled) {
                unsafe {
                    result = USB_StandardRequests(ep_out, ep_in, devDesc, sizeof(devDesc),
                        cfgDescHs, sizeof(cfgDescHs), null, 0, cfgDescFs, sizeof(cfgDescFs),
                        stringDescriptors, 4, sp, speed);
                }
            } else if (result == XUD_RES_ERR) {
                XUD_SetStall(ep_out);
                XUD_SetStall(ep_in);
            }
        }
        if (result == XUD_RES_UPDATE) {
            XUD_BusState_t state = XUD_GetBusState(ep_out, ep_in);
            if (state == XUD_BUS_RESET) {
                speed = XUD_ResetEndpoint(ep_out, ep_in);
                configured = alternate = 0;
                input_size = NCM_NTB_MAX_SIZE;
            } else {
                XUD_AckBusState(ep_out, ep_in);
            }
        }
    }
}
