:orphan:

################################################
AN02062: USB CDC-NCM Class for Ethernet over USB
################################################

:vendor: XMOS
:version: 1.0.0
:scope: Example
:description: Ethernet over USB using CDC-NCM, with a web-based board control demo
:category: Networking
:keywords: USB, Ethernet
:hardware: XK-EVK-XU316

*******
Summary
*******

This application note implements a USB Communications Device Class Network
Control Model (CDC-NCM) function using ``lib_xud``. A small IPv4 web server
allows the host to control the board LEDs, read the push buttons and view
network packet statistics at ``http://xmos-ncm.local``.

It is an NCM companion to AN00131, which demonstrates the simpler CDC-ECM
transport. NCM adds transfer-block framing and Ethernet-frame aggregation.
This is a development version, not a validated USB compliance reference.

********
Features
********

* NCM 1.0, NTB16 framing without optional datagram CRC
* USB 2.0 high-speed and full-speed descriptors
* Multiple received Ethernet frames per NTB, including chained pointer tables
* Transmit aggregation with a 250 microsecond flush timer
* Fixed-size buffers and validation of host-supplied NTB offsets and lengths
* IPv4 ARP, DHCP, ICMP echo, mDNS and HTTP demonstration
* Web page control of LEDs and display of push-button state
* Automatic page refresh on button-state changes, polled every 250 milliseconds

************
Known issues
************

* Basic high-speed operation has been checked on macOS 15.5 (24F74): native NCM
  binding, DHCP, ping, mDNS, HTTP and LED-control responses. Windows 11 and Linux,
  full-speed operation and suspend/resume still require hardware tests.
* The USB PID is a development placeholder (``0x0000``). An assigned PID and
  documentation/software part numbers are required before publication.
* Switching alternate settings or reconfiguring while bulk IN traffic is
  pending requires validation: an already-armed packet is retained until XUD
  reports completion or a bus reset.
* The inherited IPv4 stack is a small demonstration, not a production TCP/IP
  stack. It has no IPv6, TCP retransmission or IP reassembly.
* Fixed demonstration IP and MAC addresses must be made unique for products
  or multiple attached boards.

****************
Development repo
****************

* `AN02062 <https://github.com/xmosnotes/an02062>`_ (https://github.com/xmosnotes/an02062)

**************
Required tools
**************

* XMOS XTC Tools: 15.3.1

************************
Host system requirements
************************

Windows 11 includes Microsoft's ``UsbNcm.sys`` class driver. macOS and Linux
also provide NCM host drivers; supported OS versions and automatic binding
must be established by testing this implementation. Windows 10 support is
not claimed. Name resolution requires mDNS support on the host; use the
device IP address if ``xmos-ncm.local`` is unavailable.

*********************************
Required libraries (dependencies)
*********************************

* `lib_xud <https://www.xmos.com/libraries/lib_xud>`_ (https://www.xmos.com/libraries/lib_xud)
* `lib_logging <https://www.xmos.com/libraries/lib_logging>`_ (https://www.xmos.com/libraries/lib_logging)
* `lib_xassert <https://www.xmos.com/libraries/lib_xassert>`_ (https://www.xmos.com/libraries/lib_xassert)

*************************
Related application notes
*************************

* `AN00131 - USB CDC-ECM Class for Ethernet over USB <https://www.xmos.com/application-notes/an00131>`_
* `AN00124 - USB CDC Class as Virtual Serial Port <https://www.xmos.com/application-notes/an00124>`_

*******
Support
*******

This package is supported by XMOS Ltd. Issues can be raised against the software at
`www.xmos.com/support <https://www.xmos.com/support>`_ or using GitHub `issues <https://github.com/xmosnotes/an02062/issues>`_.
