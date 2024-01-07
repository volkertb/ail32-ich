// #include <stdio.h>
// #include <pc.h>
// #include <sys/nearptr.h>

//int whatever(const char *format);
//
//int whatever(const char *format) {
//    //printf("Function whatever without underscore invoked!");
//    return 0;
//}

const int ERROR = -1;

int whatever(long arg);

void write_string(int colour, const char *string, int starting_line);

int whatever(long arg) {
    //printf("Function whatever with underscore invoked!");

    // char a;
    // a = inportb(0x100);

    long starting_line = 20;
    long starting_video_address = 0xB8000 + (starting_line * 80 * 2);
    volatile char *video = (volatile char *) starting_video_address;
    if (*video == 'I' && *(video+1) == 11) {
        // Part of debugging/troubleshooting why this function is being invoked from assembly twice
        write_string(12, "Waaaaa? Invoked for a *third* time??? :O :O :O", starting_line);
    } else if (*video == 'H' && *(video+1) == 10) {
        // Part of debugging/troubleshooting why this function is being invoked from assembly twice
        write_string(11, "INVOKED FOR A SECOND TIME! :O", starting_line);
    } else {
        // Should be the one that remains on the screen if this function is infoked from assembly only once.
        write_string(10, "Hello, this is a test string :)", starting_line);
    }

    // Test to check if parameter passing from assembly code is working.
    if (arg == 0x1234) {
        write_string(9, "Value 1234 was passed in call from assembly language! :D", starting_line + 1);
    } else {
        write_string(9, "Some value other than 1234 was passed in call from assembly language.", starting_line + 1);
    }

    while (0) {
        // Infinite loop if enabled, for testing/debugging purposes
    }

    return 0;
}

/**
 * Copied from https://wiki.osdev.org/Printing_to_Screen
 * note this example will always write to the top line of the screen
 * @param colour CGA color to print the text in, for instance 10 for bright green
 * @param string string to print to screen
 * @param starting_line which line to print the text on, 0 = highest line, 1 = second highest line, etc.
 */
void write_string(int colour, const char *string, int starting_line) {
    long starting_video_address = 0xB8000 + (starting_line * 80 * 2);
    volatile char *video = (volatile char *) starting_video_address;
    while (*string != 0) {
        *video++ = *string++;
        *video++ = colour;
    }
}
