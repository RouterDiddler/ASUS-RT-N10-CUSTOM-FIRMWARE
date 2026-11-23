# ASUS-RT-N10-CUSTOM-FIRMWARE
I made a custom firmware for a ASUS RT N10 router.

If you want to use this firmware you must get uImage-flash image from the releases or use the patches with in the repository.After that get the router in flash writing mode via UART(Check the OpenWrt doc for more info) and write the uImage-Flash file(Or your own build) with TFTP.

SOME PROBLEMS

Because the routers small flash size(4 mb) I had to limit the kernel space and give it to rootfs also the router version I developed this firmware for is RT-N10 B without a USB port so it might not work in other devices

I am not responsible for any damages caused to your router.Use it with your own risk.

(This Is NOT Openwrt as there is closed source firmware)

Last thing of all is I bricked my router so I wont be able to develop this project further unfornutalitly(sorry for bad english)
