# Flight Inertia Toggle

Client-only Minecraft 1.7.10 Forge mod built for GT New Horizons 2.8.4.

- Press `F8` to enable or disable flight inertia.
- The key can be changed under Minecraft Controls.
- The selected state persists in `config/flightinertiatoggle.cfg`.
- When inertia is disabled and creative-style flight is active, releasing all horizontal movement keys stops horizontal motion immediately. Releasing Jump and Sneak stops vertical motion immediately.
- Ground movement, falling, and non-flight movement are not changed.

Build with `gradlew.bat build`. The compiled JAR is written under `build/libs`.
