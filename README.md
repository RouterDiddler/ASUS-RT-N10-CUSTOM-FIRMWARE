# ASUS RT-N10 Custom Firmware

A custom firmware project developed specifically for the **ASUS RT-N10 B** router.

## Installation

To use this firmware, you can either download the prebuilt `uImage-flash` image from the [Releases](../../releases) section or build your own image using the patches provided in this repository.

Once you have the image:

1. Connect to your router via UART.
2. Put the router into flash-writing mode (refer to the [OpenWrt documentation](https://openwrt.org/docs/techref/bootloader)).
3. Transfer the `uImage-flash` image (or your own build) to the router using TFTP.
4. Flash the image to the appropriate partition.

**Warning:** Make sure you understand the flashing process and your router's flash layout before proceeding. Flashing an incompatible image or writing to the wrong partition may permanently brick your device.

## Known Limitations

Due to the router's limited **4 MB flash capacity**, kernel space had to be reduced to make more room for the root filesystem.

Additionally, this firmware was developed specifically for the **ASUS RT-N10 B**, a hardware revision without a USB port. Compatibility with other RT-N10 revisions and similar devices is not guaranteed.

## Features

- **IPv6 Support**
- **Modern Linux Kernel**
- **Fast Boot Time**
- **Reset Button Functionality:** Holding the Reset button for 3 seconds resets the Wi-Fi settings.
- **WPS Button Functionality:** Pressing the WPS button toggles Wi-Fi on and off.

## Important Notes

- This project is **NOT OpenWrt**.
- The firmware contains closed-source components inherited from the original vendor firmware.
- Hardware compatibility is limited and has not been verified across other revisions.
- Use this firmware at your own risk. I am not responsible for any damage caused by flashing or using it.

## Project Status

Unfortunately, development has been discontinued.

I ended up bricking my own router during development, which left me unable to continue working on the project.

Thank you to everyone interested in this project.
