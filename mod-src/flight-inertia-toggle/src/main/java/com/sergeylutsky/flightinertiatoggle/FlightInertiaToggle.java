package com.sergeylutsky.flightinertiatoggle;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import cpw.mods.fml.common.Mod;
import cpw.mods.fml.common.SidedProxy;
import cpw.mods.fml.common.event.FMLInitializationEvent;
import cpw.mods.fml.common.event.FMLPreInitializationEvent;

@Mod(
    modid = FlightInertiaToggle.MODID,
    name = FlightInertiaToggle.NAME,
    version = Tags.VERSION,
    acceptedMinecraftVersions = "[1.7.10]",
    acceptableRemoteVersions = "*")
public final class FlightInertiaToggle {

    public static final String MODID = "flightinertiatoggle";
    public static final String NAME = "Flight Inertia Toggle";
    public static final Logger LOG = LogManager.getLogger(MODID);

    @SidedProxy(
        clientSide = "com.sergeylutsky.flightinertiatoggle.ClientProxy",
        serverSide = "com.sergeylutsky.flightinertiatoggle.CommonProxy")
    public static CommonProxy proxy;

    @Mod.EventHandler
    public void preInit(FMLPreInitializationEvent event) {
        proxy.preInit(event);
    }

    @Mod.EventHandler
    public void init(FMLInitializationEvent event) {
        proxy.init(event);
    }
}
