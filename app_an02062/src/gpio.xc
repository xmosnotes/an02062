// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#include <platform.h>
#include "gpio.h"

/* GPIO ports, as named in the XK-EVK-XU316 XN file.
 * LEDs are driven high to turn on, buttons read low when pressed */
on tile[0]: out port p_leds = PORT_LEDS;
on tile[0]: in port p_buttons = PORT_BUTTONS;

static unsigned ledState = 0;

void ledsSet(unsigned mask)
{
    ledState = mask & ((1 << NUM_LEDS) - 1);
    p_leds <: ledState;
}

unsigned ledsGet(void)
{
    return ledState;
}

unsigned buttonsGet(void)
{
    unsigned val;
    p_buttons :> val;
    return ~val & ((1 << NUM_BUTTONS) - 1);
}
