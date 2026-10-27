import { StaticStyles } from "./static-styles.js";
import { DynamicStyles } from "./dynamic-styles.js";
import { MainContainer } from "./container.js";
import { SplashScreen } from "./splash-screen.js";
import { SaveManager } from "./save-manager.js";
import { VolumeControls } from "./volume-controls.js";
import { UnsupportedVideo } from "./unsupported-video.js";
import { HardwareAcceleration } from "./hardware-acceleration.js";
import { ClipboardPermission } from "./clipboard-permission.js";
import { ContextMenuOverlay } from "./context-menu-overlay.js";

/*
 *
 * The shadow template which is used to fill the actual Ruffle player element
 * on the page.
 *
 * Built on first use: this module is loaded into every frame of every page,
 * and most of them never create a player.
 *
 */

let template: HTMLTemplateElement | null = null;

/**
 * Returns the shared shadow template, building it the first time.
 *
 * @returns The template to clone into each player's shadow root.
 */
export function ruffleShadowTemplate(): HTMLTemplateElement {
    if (template === null) {
        template = document.createElement("template");
        template.content.appendChild(<StaticStyles />);
        template.content.appendChild(<DynamicStyles />);
        template.content.appendChild(<MainContainer />);
        template.content.appendChild(<SplashScreen />);
        template.content.appendChild(<SaveManager />);
        template.content.appendChild(<VolumeControls />);
        template.content.appendChild(<UnsupportedVideo />);
        template.content.appendChild(<HardwareAcceleration />);
        template.content.appendChild(<ClipboardPermission />);
        template.content.appendChild(<ContextMenuOverlay />);
    }
    return template;
}
