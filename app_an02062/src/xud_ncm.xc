// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <string.h>
#include <timer.h>
#include "xud_ncm.h"

/* One receiving NTB and two transmitting NTBs. XUD always receives into a
 * separate word-aligned USB-packet buffer; untrusted lengths cannot overrun an
 * NTB. Retain completed RX data until all its datagrams have been consumed. */
#define FLUSH_TICKS (250 * XS1_TIMER_MHZ) /* 250 us maximum aggregation wait */

static unsigned packet_size(XUD_BusSpeed_t speed)
{
    return speed == XUD_SPEED_HS ? 512 : 64;
}

static void notify_start(XUD_ep ep, unsigned char data[], unsigned &pending,
                          unsigned &busy, unsigned connected, unsigned packet)
{
    if (!busy && pending) {
        memset(data, 0, 16);
        data[0] = 0xa1;
        if (pending & 1) {
            data[1] = 0x2a; /* CONNECTION_SPEED_CHANGE, control interface 0 */
            data[6] = 8;
            unsigned bitrate = packet == 512 ? 480000000 : 12000000;
            ncm_put32(data + 8, bitrate);
            ncm_put32(data + 12, bitrate);
            XUD_SetReady_In(ep, data, 16);
            pending &= ~1u;
        } else {
            data[1] = 0; /* NETWORK_CONNECTION */
            data[2] = connected; /* little-endian wValue = 0 or 1 */
            XUD_SetReady_In(ep, data, 8);
            pending &= ~2u;
        }
        busy = 1;
    }
}

void CdcNcmEndpointsHandler(chanend c_notify, chanend c_out, chanend c_in,
                            server interface usb_cdc_ncm_if ncm,
                            server interface ncm_control_if control)
{
    unsigned rx_words[NCM_NTB_MAX_SIZE / 4];
    unsigned tx_words[2][NCM_NTB_MAX_SIZE / 4];
    unsigned usb_words[512 / 4 + 2];
    unsigned notify_words[4];
    unsigned frame_words[(NCM_MAX_FRAME_SIZE + 3) / 4];
    ncm_datagram_t frames[NCM_MAX_DATAGRAMS];
    XUD_ep ep_out = XUD_InitEp(c_out);
    XUD_ep ep_notify = XUD_InitEp(c_notify);
    XUD_ep ep_in = XUD_InitEp(c_in);
    unsigned enabled = 0, configured = 0, suspended = 0;
    unsigned packet = 512, input_size = NCM_NTB_MAX_SIZE;
    unsigned rx_used = 0, rx_count = 0, rx_index = 0, rx_armed = 0, rx_drop = 0;
    unsigned build = 0, used = NCM_TX_HEADER_SIZE, count = 0, sequence = 0;
    unsigned sending = 1, tx_length = 0, tx_offset = 0, tx_busy = 0;
    unsigned tx_abort = 0, tx_retry = 0, tx_start = 0, tx_packet_length = 0;
    unsigned flush = 0, deadline = 0;
    unsigned notify_busy = 0, notify_pending = 0;
    timer flush_timer;
    unsigned length;
    XUD_Result_t result;
    ncm_ntb_init((tx_words[build], unsigned char[]), sequence);

    while (1) {
        if (enabled && !suspended && tx_busy && tx_retry) {
            XUD_SetReady_In(ep_in, (tx_words[sending], unsigned char[]) + tx_start,
                            tx_packet_length);
            tx_retry = 0;
        }
        if (enabled && !suspended && !rx_armed && !rx_count) {
            XUD_SetReady_Out(ep_out, (usb_words, unsigned char[]));
            rx_armed = 1;
        }
        if (enabled && !suspended && !tx_busy && count &&
            (flush || count == NCM_TX_DATAGRAMS ||
             NCM_FRAME_OFFSET(used) + NCM_MAX_FRAME_SIZE > input_size)) {
            sending = build;
            tx_length = ncm_ntb_finish((tx_words[sending], unsigned char[]), used, count);
            build ^= 1;
            ncm_ntb_init((tx_words[build], unsigned char[]), ++sequence);
            used = NCM_TX_HEADER_SIZE;
            count = flush = 0;
            tx_offset = tx_length > packet ? packet : tx_length;
            tx_busy = 1;
            tx_abort = 0;
            tx_start = 0;
            tx_packet_length = tx_offset;
            XUD_SetReady_In(ep_in, (tx_words[sending], unsigned char[]), tx_offset);
        }
        if (configured && !suspended)
            notify_start(ep_notify, (notify_words, unsigned char[]),
                         notify_pending, notify_busy, enabled, packet);
        select {
        case control.set_link(unsigned config, unsigned alternate):
            configured = config;
            enabled = config && alternate;
            rx_used = rx_count = rx_index = rx_drop = 0;
            count = flush = 0;
            used = NCM_TX_HEADER_SIZE;
            sequence = 0;
            ncm_ntb_init((tx_words[build], unsigned char[]), sequence);
            /* Never overwrite a buffer still owned by XUD. */
            if (tx_busy)
                tx_abort = 1;
            notify_pending = config ? 3 : 0;
            break;

        case control.set_input_size(unsigned size) -> unsigned accepted:
            /* The host sized its outstanding read, and the terminating ZLP
             * decision, from the current limit: keep it until the NTB is sent. */
            accepted = size >= 2048 && size <= NCM_NTB_MAX_SIZE &&
                       (!tx_busy || size == input_size);
            if (accepted) {
                input_size = size;
                if (used > size) {
                    count = flush = 0;
                    used = NCM_TX_HEADER_SIZE;
                    ncm_ntb_init((tx_words[build], unsigned char[]), sequence);
                }
            }
            break;

        case (count && !flush) => flush_timer when timerafter(deadline) :> void:
            flush = 1;
            break;

        case XUD_GetData_Select(c_out, ep_out, length, result):
            rx_armed = 0;
            if (result == XUD_RES_UPDATE) {
                XUD_BusState_t state = XUD_GetBusState(ep_out, null);
                if (state == XUD_BUS_RESET) {
                    packet = packet_size(XUD_ResetEndpoint(ep_out, null));
                    configured = enabled = 0;
                    rx_used = rx_count = rx_index = rx_drop = 0;
                    input_size = NCM_NTB_MAX_SIZE;
                    suspended &= ~1u;
                } else {
                    if (state == XUD_BUS_SUSPEND) suspended |= 1;
                    if (state == XUD_BUS_RESUME) suspended &= ~1u;
                    XUD_AckBusState(ep_out, null);
                }
            } else if (result == XUD_RES_OKAY && enabled) {
                if (length > NCM_NTB_MAX_SIZE - rx_used)
                    rx_drop = 1;
                if (!rx_drop) {
                    memcpy((rx_words, unsigned char[]) + rx_used,
                           (usb_words, unsigned char[]), length);
                    rx_used += length;
                }
                unsigned declared = rx_used >= 12 ?
                    ncm_get16((rx_words, unsigned char[]) + 8) : 0;
                if (length < packet || rx_used == NCM_NTB_MAX_SIZE ||
                    (!rx_drop && declared >= 12 && rx_used >= declared)) {
                    if (!rx_drop && rx_used) {
                        int parsed = ncm_ntb_parse((rx_words, unsigned char[]), rx_used, frames);
                        rx_count = parsed > 0 ? parsed : 0;
                    }
                    rx_index = rx_used = rx_drop = 0;
                }
            }
            break;

        case XUD_SetData_Select(c_in, ep_in, result):
            if (result == XUD_RES_UPDATE) {
                XUD_BusState_t state = XUD_GetBusState(ep_in, null);
                if (state == XUD_BUS_RESET) {
                    XUD_ResetEndpoint(ep_in, null);
                    configured = enabled = 0;
                    tx_busy = tx_abort = tx_retry = count = flush = 0;
                    used = NCM_TX_HEADER_SIZE;
                    sequence = 0;
                    ncm_ntb_init((tx_words[build], unsigned char[]), sequence);
                    suspended &= ~2u;
                } else {
                    if (state == XUD_BUS_SUSPEND) {
                        suspended |= 2;
                        tx_retry = tx_busy;
                    }
                    if (state == XUD_BUS_RESUME) {
                        suspended &= ~2u;
                    }
                    XUD_AckBusState(ep_in, null);
                }
            } else if (result == XUD_RES_OKAY) {
                if (tx_abort || !enabled) {
                    tx_busy = tx_abort = 0;
                } else if (tx_offset < tx_length) {
                    unsigned bytes = tx_length - tx_offset;
                    if (bytes > packet) bytes = packet;
                    tx_start = tx_offset;
                    tx_packet_length = bytes;
                    XUD_SetReady_In(ep_in, (tx_words[sending], unsigned char[]) + tx_offset, bytes);
                    tx_offset += bytes;
                } else if (tx_offset == tx_length && tx_length % packet == 0 &&
                           tx_length < input_size) {
                    /* Terminate a short NTB whose last USB packet was full. */
                    XUD_SetReady_In(ep_in, (tx_words[sending], unsigned char[]), 0);
                    tx_start = tx_packet_length = 0;
                    tx_offset++;
                } else {
                    tx_busy = 0;
                }
            } else if (tx_busy) {
                /* Do not reuse an in-flight buffer after an unexpected error. */
                tx_busy = tx_abort = 0;
            }
            break;

        case XUD_SetData_Select(c_notify, ep_notify, result):
            notify_busy = 0;
            if (result == XUD_RES_UPDATE) {
                XUD_BusState_t state = XUD_GetBusState(ep_notify, null);
                if (state == XUD_BUS_RESET) {
                    XUD_ResetEndpoint(ep_notify, null);
                    notify_pending = configured = enabled = 0;
                    suspended &= ~4u;
                } else {
                    if (state == XUD_BUS_SUSPEND) suspended |= 4;
                    if (state == XUD_BUS_RESUME) {
                        suspended &= ~4u;
                        if (configured) notify_pending = 3;
                    }
                    XUD_AckBusState(ep_notify, null);
                }
            }
            break;

        case (enabled && rx_index < rx_count) =>
                ncm.read_frame(unsigned char buf[], unsigned &frame_length):
            frame_length = frames[rx_index].length;
            memcpy(buf, (rx_words, unsigned char[]) + frames[rx_index].offset, frame_length);
            if (++rx_index == rx_count)
                rx_count = rx_index = 0;
            break;

        case (enabled && count < NCM_TX_DATAGRAMS &&
              NCM_FRAME_OFFSET(used) + NCM_MAX_FRAME_SIZE <= input_size) =>
                ncm.send_frame(unsigned char buf[], unsigned &frame_length):
            if (frame_length < 14 || frame_length > NCM_MAX_FRAME_SIZE)
                break;
            memcpy((frame_words, unsigned char[]), buf, frame_length);
            unsigned next = ncm_ntb_append((tx_words[build], unsigned char[]),
                                           used, count, (frame_words, unsigned char[]),
                                           frame_length, input_size);
            if (next) {
                used = next;
                if (!count) {
                    flush_timer :> deadline;
                    deadline += FLUSH_TICKS;
                }
                count++;
            }
            break;

        case ncm.is_frame_available() -> int available:
            available = enabled && rx_index < rx_count;
            break;
        }
    }
}
