1. player.gd & player_stats.gd: A persistent data vault that holds identities, names, and tracks mid-game variable changes while being 100% immune to character deaths.
2. players_service.gd: A global manager that captures engine network traffic, handles player metadata snapshots, manages late-joiner catchup packets seamlessly, and forces authoritative server rules.
3. steam_network.gd: A secure transport wrapper using GodotSteam that activates Valve's P2P relays, opens lobbies, and coordinates peer sockets without touching game code.
4. multiplayer_world.gd: A multi-axis workspace spawner that automatically figures out 2D/3D planes, recursively loops over spawn points, assigns proper authorities, and executes safe async respawning timers.
5. main.gd: The lightweight UI controller that toggles instantly between online Steam play and offline multi-instance ENet testing with a single click.
