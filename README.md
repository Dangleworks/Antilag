# AntiLag
Please keep in mind, this is a work-in-progress, and there can be some issues. Please report any problems [here](https://github.com/Dangleworks/Antilag/issues)
## Commands
There's only only really one command, `?antilag config`, which allows you to change almost all the settings on the fly without reloading the script. Any changes you make with the command will be saved to the world, and will reset if you reset the world file.

Running `?antilag config` will show you the current settings. To change a setting, run `?antilag config <option> <value>`

### Default Options
These can be changed in `script.lua` or using `?antilag config`
| Option                     | Default | Description |
|----------------------------|---------|-------------|
| base_vehicle_limit         | 1       | The vehicle limit of all unverified users
| auth_vehicle_limit         | 3       | The vehicle limit of all verified users
| nitro_vehicle_limit        | 5       | This is unused, but could be implemented later
| max_mass                   | 70000   | The maximum spawn mass for a vehicle
| tps_threshhold             | 45      | The minimum TPS for the addon to maintain, below this limit vehicle spawning will automatically be disabled
| load_time_threshold        | 3000    | Time in milliseconds for a vehicle to finish spawning
| tps_recover_time           | 4000    | Time im milliseconds for TPS average to recover after a vehicle spawns
| auto_despawn_vehicle_limit | true    | Whether to despawn old vehicles, or prevent spawning altogether when a user has reached their vehicle limit
| admin_bypass_vehicle_limit | false   | Self explanatory
| disable_vehicle_limit      | false   | Self explanatory
| tps_avg_diff_threshold     | 15      | For advanced users, default is usually fine
| vehicle_stabilize_chances  | 1       | The amount of tries a vehicle has for average TPS to normalize before being despawned
| remove_objects             | true    | Automatically despawn flares, dropped items, grenades, C4, etc.

## Vehicle Limits
The AntiLag has vehicle limiting built in, and works well with [DiscordAuth](https://github.com/Dangleworks/DiscordAuth) and [DiscordAuthAddon](https://github.com/Dangleworks/DiscordAuthAddon). Like on Dangleworks, with the default settings, all users can spawn 1 vehicle, this limit can be raised by verifying on Discord with `?verify` and `^verify <code>`. Vehicle limits can be disabled for admins, or for everyone using `?antilag config admin_bypass_vehicle_limit true` and `?antilag config disable_vehicle_limit true` respectively, these can also be changed in the `script.lua` file if you want it to persist between world resets.