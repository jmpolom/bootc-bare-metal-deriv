# Install to bare metal

Run on a Linux installation host with udev active, a usable TPM2, and sufficient
space in `/var/tmp`. Replace the disk IDs below with two distinct, unmounted
whole-disk paths. **This erases both disks.**

```sh
backend=composefs # Use ostree for the OSTree image and installer.
arch=x86_64      # Use aarch64 on an ARM64 host.
image="ghcr.io/jmpolom/bootc-bare-metal-deriv:44-main-${backend}-${arch}"

sudo install -d -m 0700 /var/lib/bootc-metal-install
sudo podman run --rm --pull=always --privileged \
    --user 0:0 --userns host --cap-add all --pid=host --ipc=host \
    --security-opt label=type:unconfined_t \
    --volume /dev:/dev \
    --volume /run/udev:/run/udev:ro \
    --volume /var/lib/containers:/var/lib/containers \
    --volume /var/lib/containers/storage:/run/host-container-storage:ro \
    --volume /var/tmp:/var/tmp \
    --volume /var/lib/bootc-metal-install:/run/bootc-metal-install \
    --env ROOT_DISK=/dev/disk/by-id/ROOT_DISK_ID \
    --env DATA_DISK=/dev/disk/by-id/DATA_DISK_ID \
    --entrypoint "/usr/libexec/bootc-installer/install-${backend}.sh" \
    "$image" -c /usr/libexec/bootc-installer/bare-metal-default.env -y
```

Save `/var/lib/bootc-metal-install/recovery-keys.txt` securely after installation.
The bundled config enables LUKS/TPM2 encryption and creates the `test-admin` user;
review its account settings before building an image for a real host.
