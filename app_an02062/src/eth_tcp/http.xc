// Copyright 2015-2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <ethernet.h>
#include <print.h>
#include <string.h>
#include <stdio.h>
#include "femtoTCP.h"
#include "gpio.h"

/* The demo TCP stack sends each response as a single TCP segment, so the whole
 * response must fit in one Ethernet frame:
 * 1514 - 14 (Ethernet header) - 20 (IP header) - 20 (TCP header) = 1460 bytes */
#define HTTP_MAX_RESPONSE   1460

/* Number of bytes of the request line that are examined, e.g. "GET /?led=15 " */
#define REQ_LEN             32

/* Reserve space for the HTTP status line and headers within the one-segment
 * response limit, even when all packet counters grow to ten digits. */
static char body[HTTP_MAX_RESPONSE - 100 + 1];
static char response[HTTP_MAX_RESPONSE + 1];
static unsigned bodyLen;

/* Poll only after the preceding request completes. Compare against the state
 * rendered into the page, so changes before the first poll are not missed.
 * A failed request is retried; it must not stop later button updates. */
static const char buttonScript[] =
    "const shown=Number(document.body.dataset.buttons);\n"
    "async function pollButtons(){\n"
    " const abort=new AbortController();\n"
    " const timeout=setTimeout(()=>abort.abort(),2000);\n"
    " try{\n"
    "  const r=await fetch('/buttons',{cache:'no-store',signal:abort.signal});\n"
    "  const state=Number(await r.text());\n"
    "  if(r.ok&&Number.isInteger(state)&&state!==shown){\n"
    "   location.replace('/');return;\n"
    "  }\n"
    " }catch(e){}finally{clearTimeout(timeout);}\n"
    " setTimeout(pollButtons,250);\n"
    "}\n"
    "setTimeout(pollButtons,250);\n";

/* Keep styling in its own response rather than growing the single-frame page. */
static const char pageStyle[] =
    ":root{font:15px system-ui,sans-serif;color:#19304a;background:#edf3f8}"
    "body{max-width:760px;margin:40px auto;padding:0 20px}"
    "h1{font-size:22px;background:#12324d;color:white;padding:24px;border-radius:14px}"
    "small{display:block;font-size:11px;font-weight:400;letter-spacing:.1em;"
    "text-transform:uppercase;margin-top:8px;color:#a7d4f1}"
    "h2{text-transform:uppercase;font-size:12px;letter-spacing:.12em;"
    "color:#51677c;margin:26px 0 12px}"
    "table{width:100%;border-collapse:separate;border-spacing:0;background:white;"
    "border-radius:12px;overflow:hidden;box-shadow:0 4px 20px #16334d0d}"
    /* Rows with and without a link are the same height. Values and links sit
     * on the right; LED and button states are centred. */
    "td{padding:10px 14px;border-bottom:1px solid #edf3f8}"
    "tr:last-child td{border:0}"
    "td+td{text-align:right;font-variant-numeric:tabular-nums}"
    ".on,.off{text-align:center;width:30%;height:30px}"
    ".on{background:#dcfce7;color:#166534;font-weight:700}"
    ".off{background:#f1f5f9;color:#64748b}"
    "a{display:inline-block;padding:6px 12px;border-radius:7px;background:#e0efff;"
    "color:#12528b;text-decoration:none}"
    "a:hover,a:focus{background:#c5e2ff}"
    "@media(max-width:500px){body{margin:16px auto}td{padding:8px}}";

/* Append formatted text to the page body, truncating if it does not fit */
#define APPEND(...) \
    do { \
        int n = snprintf(body + bodyLen, sizeof(body) - bodyLen, __VA_ARGS__); \
        if (n > 0) bodyLen += n; \
        if (bodyLen >= sizeof(body)) bodyLen = sizeof(body) - 1; \
    } while (0)

static void buildPage(void)
{
    unsigned leds = ledsGet();
    unsigned buttons = buttonsGet();

    bodyLen = 0;

    APPEND("<!DOCTYPE html>\n<html><head><title>XMOS CDC-NCM</title>\n"
           "<meta name=viewport content=\"width=device-width\">\n"
           "<link rel=stylesheet href=\"/style.css\">\n"
           "<script src=\"/buttons.js\" defer></script>\n"
           "</head><body data-buttons=\"%u\">\n"
           "<h1>XMOS CDC-NCM<small>Ethernet over USB</small></h1>\n", buttons);

    /* Board controls. Each link carries the complete LED mask to apply, so
     * refreshing the page does not change the LEDs again */
    APPEND("<h2>Board controls</h2>\n<table>\n");
    for (int i = 0; i < NUM_LEDS; i++) {
        unsigned ledOn = (leds >> i) & 1;
        APPEND("<tr><td>LED %d</td><td class=%s>%s</td><td><a href=\"/?led=%u\">Turn %s</a></td></tr>\n",
               i, ledOn ? "on" : "off", ledOn ? "On" : "Off",
               leds ^ (1 << i), ledOn ? "off" : "on");
    }
    for (int i = 0; i < NUM_BUTTONS; i++) {
        unsigned pressed = (buttons >> i) & 1;
        APPEND("<tr><td>Button %d</td><td class=%s>%s</td><td></td></tr>\n",
               i, pressed ? "on" : "off", pressed ? "Pressed" : "Released");
    }
    APPEND("</table>\n");

    /* Network statistics. Button changes reload the page automatically; the
     * Refresh link updates the counters on demand. */
    APPEND("<h2>Network statistics</h2>\n<table>\n");
    APPEND("<tr><td>Packets received</td><td>%u</td></tr>\n", stats.total_rx_packets);
    APPEND("<tr><td>Packets transmitted</td><td>%u</td></tr>\n", stats.total_tx_packets);
    APPEND("<tr><td>ARP packets received</td><td>%u</td></tr>\n", stats.arp_rx_packets);
    APPEND("<tr><td>TCP packets received</td><td>%u</td></tr>\n", stats.tcp_rx_packets);
    APPEND("<tr><td>UDP packets received</td><td>%u</td></tr>\n", stats.udp_rx_packets);
    APPEND("<tr><td>ICMP packets received</td><td>%u</td></tr>\n", stats.icmp_rx_packets);
    APPEND("<tr><td>Bytes received</td><td>%u</td></tr>\n", stats.total_rx_bytes);
    APPEND("<tr><td>Bytes transmitted</td><td>%u</td></tr>\n", stats.total_tx_bytes);
    APPEND("</table>\n<p><a href=\"/\">Refresh</a></p>\n</body></html>\n");
}

static void sendResponse(const char content_type[], const char content[],
                         unsigned int rsp_packet[], unsigned &rsp_len)
{
    /* No cached button snapshots or stale page state after a reload. */
    int n = snprintf(response, sizeof(response),
                     "HTTP/1.0 200 OK\r\nContent-Type: %s\r\n"
                     "Cache-Control: no-store\r\nContent-Length: %u\r\n\r\n%s",
                     content_type, strlen(content), content);
    if (n < 0 || n >= sizeof(response)) {
        tcpString("HTTP/1.0 500 Internal Server Error\r\nContent-Length: 0\r\n\r\n",
                  rsp_packet, rsp_len);
        return;
    }
    tcpString(response, rsp_packet, rsp_len);
}

static void sendPage(unsigned int rsp_packet[], unsigned &rsp_len)
{
    buildPage();
    sendResponse("text/html", body, rsp_packet, rsp_len);
}

void httpProcess(unsigned int packet[], int charOffset, int packetLength, unsigned int rsp_packet[], unsigned &rsp_len)
{
    char request[REQ_LEN];
    int len = (packetLength < REQ_LEN - 1) ? packetLength : REQ_LEN - 1;

    for (int i = 0; i < len; i++) {
        request[i] = (packet, unsigned char[])[charOffset + i];
    }
    request[len] = 0;

    if (strncmp(request, "GET /buttons ", 13) == 0) {
        char state[12];
        snprintf(state, sizeof(state), "%u\n", buttonsGet());
        sendResponse("text/plain", state, rsp_packet, rsp_len);
    } else if (strncmp(request, "GET /buttons.js ", 16) == 0) {
        sendResponse("application/javascript", buttonScript, rsp_packet, rsp_len);
    } else if (strncmp(request, "GET /style.css ", 15) == 0) {
        sendResponse("text/css", pageStyle, rsp_packet, rsp_len);
    } else if (strncmp(request, "GET /?led=", 10) == 0) {
        /* Set the LEDs from the decimal mask in the URL, then return the page */
        unsigned mask = 0;
        for (int i = 10; request[i] >= '0' && request[i] <= '9'; i++) {
            mask = (mask * 10) + (request[i] - '0');
        }
        ledsSet(mask);
        sendPage(rsp_packet, rsp_len);
    } else if ((strncmp(request, "GET / ", 6) == 0) || (strncmp(request, "GET /?", 6) == 0)) {
        sendPage(rsp_packet, rsp_len);
    } else {
        /* Anything else, e.g. /favicon.ico */
        tcpString("HTTP/1.0 404 NOT FOUND\r\n\r\n", rsp_packet, rsp_len);
    }
}
