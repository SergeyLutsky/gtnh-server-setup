package com.sergeylutsky.flightinertiatoggle;

import net.minecraft.client.Minecraft;
import net.minecraft.client.entity.EntityPlayerSP;
import net.minecraft.client.settings.KeyBinding;
import net.minecraft.util.ChatComponentText;

import org.lwjgl.input.Keyboard;

import cpw.mods.fml.common.eventhandler.SubscribeEvent;
import cpw.mods.fml.common.gameevent.TickEvent;

public final class FlightInertiaHandler {

    private static final float INPUT_EPSILON = 0.0001F;

    private final KeyBinding toggleKey = new KeyBinding(
        "key.flightinertiatoggle.toggle",
        Keyboard.KEY_F8,
        "key.categories.flightinertiatoggle");

    public KeyBinding getToggleKey() {
        return toggleKey;
    }

    @SubscribeEvent
    public void onClientTick(TickEvent.ClientTickEvent event) {
        if (event.phase != TickEvent.Phase.END) {
            return;
        }

        Minecraft minecraft = Minecraft.getMinecraft();
        EntityPlayerSP player = minecraft.thePlayer;

        while (toggleKey.isPressed()) {
            boolean enabled = Config.toggleInertia();
            if (player != null) {
                player.addChatMessage(new ChatComponentText("Flight inertia: " + (enabled ? "enabled" : "disabled")));
            }
        }

        if (player == null || Config.isInertiaEnabled() || !player.capabilities.isFlying) {
            return;
        }

        boolean horizontalInput = Math.abs(player.movementInput.moveForward) > INPUT_EPSILON
            || Math.abs(player.movementInput.moveStrafe) > INPUT_EPSILON;
        if (!horizontalInput) {
            player.motionX = 0.0D;
            player.motionZ = 0.0D;
        }

        if (!player.movementInput.jump && !player.movementInput.sneak) {
            player.motionY = 0.0D;
        }
    }
}
