// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.

#ifndef _GPIO_H_
#define _GPIO_H_

/* XK-EVK-XU316 general purpose LEDs and push-buttons */
#define NUM_LEDS        4
#define NUM_BUTTONS     2

/* Set the LEDs from a bit mask, bit n set turns LED n on */
void ledsSet(unsigned mask);

/* Returns the LED bit mask last set by ledsSet() */
unsigned ledsGet(void);

/* Returns the button state as a bit mask, bit n set means button n is pressed */
unsigned buttonsGet(void);

#endif
