# NIXOS hardware file

`hardware-configuration.nix` is intentionally a guard placeholder. After the minimal NixOS installation on the ThinkPad T480, overwrite it with:

```bash
sudo cp /etc/nixos/hardware-configuration.nix ./hosts/NIXOS/hardware-configuration.nix
sudo chown "$USER:$(id -gn)" ./hosts/NIXOS/hardware-configuration.nix
git add hosts/NIXOS/hardware-configuration.nix
```

Do not reuse this generated file for another machine without regenerating it.
