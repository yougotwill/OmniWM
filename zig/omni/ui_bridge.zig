const abi = @import("abi_types.zig");
const wm_controller = @import("wm_controller.zig");

pub fn omni_ui_bridge_submit_hotkey_impl(
    controller: [*c]wm_controller.OmniWMController,
    command: ?*const abi.OmniControllerCommand,
) i32 {
    return wm_controller.omni_wm_controller_submit_hotkey_impl(controller, command);
}

pub fn omni_ui_bridge_apply_settings_impl(
    controller: [*c]wm_controller.OmniWMController,
    settings_delta: ?*const abi.OmniControllerSettingsDelta,
) i32 {
    return wm_controller.omni_wm_controller_apply_settings_impl(controller, settings_delta);
}

pub fn omni_ui_bridge_query_ui_state_impl(
    controller: [*c]const wm_controller.OmniWMController,
    out_state: ?*abi.OmniControllerUiState,
) i32 {
    return wm_controller.omni_wm_controller_query_ui_state_impl(controller, out_state);
}

pub fn omni_ui_bridge_export_workspace_state_impl(
    controller: [*c]wm_controller.OmniWMController,
    out_export: ?*abi.OmniWorkspaceRuntimeStateExport,
) i32 {
    return wm_controller.omni_wm_controller_export_workspace_state_impl(controller, out_export);
}
