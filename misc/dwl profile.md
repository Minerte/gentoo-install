# DWL setup




add this to the ~/.bash_profile

```
### existing code ###
# Ensure runtime directory exists (handled by turnstile)
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Force wlroots to use seatd/libseat
export WLR_BACKENDS=drm,libinput
export WLR_LIBSEAT_BACKEND=libseat

# Only run dwl automatically if we are on TTY 1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec dwl
fi
```

then wen we log in to the tty 1 it will try to launch dwl. (if seatd, config.def.h and drivers are configured correctly)