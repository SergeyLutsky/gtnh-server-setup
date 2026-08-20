package com.sergeylutsky.flightinertiatoggle;

import java.io.File;

import net.minecraftforge.common.config.Configuration;
import net.minecraftforge.common.config.Property;

public final class Config {

    private static Configuration configuration;
    private static Property inertiaEnabledProperty;
    private static boolean inertiaEnabled = true;

    private Config() {}

    public static void load(File configFile) {
        configuration = new Configuration(configFile);
        configuration.load();
        inertiaEnabledProperty = configuration.get(
            Configuration.CATEGORY_GENERAL,
            "inertiaEnabled",
            inertiaEnabled,
            "When false, flight stops immediately after movement keys are released.");
        inertiaEnabled = inertiaEnabledProperty.getBoolean(inertiaEnabled);
        saveIfChanged();
    }

    public static boolean isInertiaEnabled() {
        return inertiaEnabled;
    }

    public static boolean toggleInertia() {
        inertiaEnabled = !inertiaEnabled;
        inertiaEnabledProperty.set(inertiaEnabled);
        saveIfChanged();
        return inertiaEnabled;
    }

    private static void saveIfChanged() {
        if (configuration.hasChanged()) {
            configuration.save();
        }
    }
}
