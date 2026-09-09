#!/bin/bash
# fe02-update: Updates the booted image, Flatpaks, and Distrobox containers

set -e

function show_usage() {
    echo "Fe02-OS Update"
    echo "Usage: fe02-update [command]"
    echo ""
    echo "Commands:"
    echo "  (none)   - Update the image, Flatpaks, and Distrobox containers"
    echo "  status   - Show current booted and staged images"
}

IMAGE_STAGED=0

function update_image() {
    echo -n "==> Upgrading system image "
    # Routed through fe02-update-image.service (see the matching polkit
    # rule) so this never needs a sudo password, e.g. when launched from
    # the desktop entry. Started non-blocking so we can print dots while it
    # runs, since the unit's own output only goes to the journal.
    systemctl start --no-block fe02-update-image.service
    local invocation_id
    invocation_id="$(systemctl show -p InvocationID --value fe02-update-image.service)"

    while [ "$(systemctl is-active fe02-update-image.service)" = "activating" ]; do
        echo -n "."
        sleep 1
    done
    echo ""

    if systemctl is-failed --quiet fe02-update-image.service; then
        echo "Image upgrade failed. See: journalctl -xeu fe02-update-image.service"
        return 1
    fi

    # bootc status requires root, so instead of querying it directly (which
    # fe02-update, run unprivileged, can't do), scope the journal to just
    # this run via its invocation ID and look for bootc's own "staged a new
    # deployment" message.
    if journalctl "_SYSTEMD_INVOCATION_ID=${invocation_id}" 2>/dev/null | grep -q "^Queued for next boot:"; then
        IMAGE_STAGED=1
    fi
}

function update_flatpaks() {
    if ! command -v flatpak &>/dev/null; then
        echo "==> Flatpak not found, skipping."
        return
    fi
    echo "==> Updating Flatpaks..."
    flatpak update -y
}

function update_distrobox() {
    if ! command -v distrobox &>/dev/null; then
        echo "==> Distrobox not found, skipping."
        return
    fi
    echo "==> Updating Distrobox containers..."
    distrobox upgrade --all
}

case "$1" in
    "")
        update_image
        update_flatpaks
        update_distrobox
        echo ""
        if [ "$IMAGE_STAGED" -eq 1 ]; then
            echo "A new system image is staged."
            read -p "Reboot now? (y/N): " confirm
            if [[ $confirm == [yY] ]]; then
                # Plain reboot, not sudo: systemd-logind authorizes it for
                # the active local session without a password, same as the
                # desktop's own Restart button.
                reboot
            else
                echo "Reboot later to apply the new image."
            fi
        else
            echo "Update complete. No new image was staged."
        fi
        ;;
    status)
        # bootc status requires root even for a read-only query.
        sudo bootc status | grep -E "Booted|Queued|Image:"
        ;;
    -h|--help)
        show_usage
        ;;
    *)
        echo "Error: Unknown command '$1'"
        show_usage
        exit 1
        ;;
esac
