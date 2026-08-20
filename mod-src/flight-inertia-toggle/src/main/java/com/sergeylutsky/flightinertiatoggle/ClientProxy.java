package com.sergeylutsky.flightinertiatoggle;

import cpw.mods.fml.client.registry.ClientRegistry;
import cpw.mods.fml.common.FMLCommonHandler;
import cpw.mods.fml.common.event.FMLInitializationEvent;
import cpw.mods.fml.common.event.FMLPreInitializationEvent;

public final class ClientProxy extends CommonProxy {

    @Override
    public void preInit(FMLPreInitializationEvent event) {
        Config.load(event.getSuggestedConfigurationFile());
    }

    @Override
    public void init(FMLInitializationEvent event) {
        FlightInertiaHandler handler = new FlightInertiaHandler();
        ClientRegistry.registerKeyBinding(handler.getToggleKey());
        FMLCommonHandler.instance()
            .bus()
            .register(handler);
        FlightInertiaToggle.LOG.info(
            "Flight inertia starts {}. Press F8 (rebindable in Controls) to toggle it.",
            Config.isInertiaEnabled() ? "enabled" : "disabled");
    }
}
