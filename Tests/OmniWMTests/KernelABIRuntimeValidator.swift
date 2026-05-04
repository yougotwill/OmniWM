// SPDX-License-Identifier: GPL-2.0-only
//
// ABI-07 (Phase 06): generated Swift validation helpers for the kernel ABI.
//
// GENERATED FILE — do not edit by hand. Regenerate with:
//
//     make regen-kernel-abi-goldens
//
// `KernelABIRuntimeValidator.validate()` returns a list of layout
// mismatches between the live `MemoryLayout<T>` values and the committed
// goldens. An empty array means the runtime layout matches the schema.
// `KernelABIRuntimeValidator.expectedSchemaVersion` is the version baked
// into this generated file; callers should compare against
// `KernelABISchema.schemaVersion` to detect cross-artifact version skew.

import COmniWMKernels
import Foundation

enum KernelABIRuntimeValidator {
    struct Mismatch: Equatable {
        let name: String
        let expected: KernelABISchemaEntry
        let actual: KernelABISchemaEntry
    }

    static let expectedSchemaVersion: Int = 1

    static func validate() -> [Mismatch] {
        var mismatches: [Mismatch] = []
        check("omniwm_axis_input", omniwm_axis_input.self, expected: KernelABISchemaEntry(name: "omniwm_axis_input", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_axis_output", omniwm_axis_output.self, expected: KernelABISchemaEntry(name: "omniwm_axis_output", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_dwindle_layout_input", omniwm_dwindle_layout_input.self, expected: KernelABISchemaEntry(name: "omniwm_dwindle_layout_input", size: 160, stride: 160, alignment: 8), into: &mismatches)
        check("omniwm_dwindle_node_input", omniwm_dwindle_node_input.self, expected: KernelABISchemaEntry(name: "omniwm_dwindle_node_input", size: 48, stride: 48, alignment: 8), into: &mismatches)
        check("omniwm_dwindle_node_frame", omniwm_dwindle_node_frame.self, expected: KernelABISchemaEntry(name: "omniwm_dwindle_node_frame", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_niri_layout_input", omniwm_niri_layout_input.self, expected: KernelABISchemaEntry(name: "omniwm_niri_layout_input", size: 144, stride: 144, alignment: 8), into: &mismatches)
        check("omniwm_niri_container_input", omniwm_niri_container_input.self, expected: KernelABISchemaEntry(name: "omniwm_niri_container_input", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_niri_window_input", omniwm_niri_window_input.self, expected: KernelABISchemaEntry(name: "omniwm_niri_window_input", size: 56, stride: 56, alignment: 8), into: &mismatches)
        check("omniwm_niri_hidden_placement_monitor", omniwm_niri_hidden_placement_monitor.self, expected: KernelABISchemaEntry(name: "omniwm_niri_hidden_placement_monitor", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_niri_container_output", omniwm_niri_container_output.self, expected: KernelABISchemaEntry(name: "omniwm_niri_container_output", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_niri_window_output", omniwm_niri_window_output.self, expected: KernelABISchemaEntry(name: "omniwm_niri_window_output", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_niri_topology_column_input", omniwm_niri_topology_column_input.self, expected: KernelABISchemaEntry(name: "omniwm_niri_topology_column_input", size: 32, stride: 32, alignment: 8), into: &mismatches)
        check("omniwm_niri_topology_window_input", omniwm_niri_topology_window_input.self, expected: KernelABISchemaEntry(name: "omniwm_niri_topology_window_input", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_geometry_snap_target_result", omniwm_geometry_snap_target_result.self, expected: KernelABISchemaEntry(name: "omniwm_geometry_snap_target_result", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_niri_topology_input", omniwm_niri_topology_input.self, expected: KernelABISchemaEntry(name: "omniwm_niri_topology_input", size: 152, stride: 152, alignment: 8), into: &mismatches)
        check("omniwm_niri_topology_column_output", omniwm_niri_topology_column_output.self, expected: KernelABISchemaEntry(name: "omniwm_niri_topology_column_output", size: 24, stride: 24, alignment: 8), into: &mismatches)
        check("omniwm_niri_topology_window_output", omniwm_niri_topology_window_output.self, expected: KernelABISchemaEntry(name: "omniwm_niri_topology_window_output", size: 8, stride: 8, alignment: 8), into: &mismatches)
        check("omniwm_niri_topology_result", omniwm_niri_topology_result.self, expected: KernelABISchemaEntry(name: "omniwm_niri_topology_result", size: 120, stride: 120, alignment: 8), into: &mismatches)
        check("omniwm_overview_context", omniwm_overview_context.self, expected: KernelABISchemaEntry(name: "omniwm_overview_context", size: 120, stride: 120, alignment: 8), into: &mismatches)
        check("omniwm_overview_workspace_input", omniwm_overview_workspace_input.self, expected: KernelABISchemaEntry(name: "omniwm_overview_workspace_input", size: 16, stride: 16, alignment: 4), into: &mismatches)
        check("omniwm_overview_generic_window_input", omniwm_overview_generic_window_input.self, expected: KernelABISchemaEntry(name: "omniwm_overview_generic_window_input", size: 48, stride: 48, alignment: 8), into: &mismatches)
        check("omniwm_overview_niri_tile_input", omniwm_overview_niri_tile_input.self, expected: KernelABISchemaEntry(name: "omniwm_overview_niri_tile_input", size: 8, stride: 8, alignment: 8), into: &mismatches)
        check("omniwm_overview_niri_column_input", omniwm_overview_niri_column_input.self, expected: KernelABISchemaEntry(name: "omniwm_overview_niri_column_input", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_overview_section_output", omniwm_overview_section_output.self, expected: KernelABISchemaEntry(name: "omniwm_overview_section_output", size: 136, stride: 136, alignment: 8), into: &mismatches)
        check("omniwm_overview_generic_window_output", omniwm_overview_generic_window_output.self, expected: KernelABISchemaEntry(name: "omniwm_overview_generic_window_output", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_overview_niri_tile_output", omniwm_overview_niri_tile_output.self, expected: KernelABISchemaEntry(name: "omniwm_overview_niri_tile_output", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_overview_niri_column_output", omniwm_overview_niri_column_output.self, expected: KernelABISchemaEntry(name: "omniwm_overview_niri_column_output", size: 48, stride: 48, alignment: 8), into: &mismatches)
        check("omniwm_overview_drop_zone_output", omniwm_overview_drop_zone_output.self, expected: KernelABISchemaEntry(name: "omniwm_overview_drop_zone_output", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_overview_result", omniwm_overview_result.self, expected: KernelABISchemaEntry(name: "omniwm_overview_result", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_restore_snapshot", omniwm_restore_snapshot.self, expected: KernelABISchemaEntry(name: "omniwm_restore_snapshot", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_restore_monitor", omniwm_restore_monitor.self, expected: KernelABISchemaEntry(name: "omniwm_restore_monitor", size: 56, stride: 56, alignment: 8), into: &mismatches)
        check("omniwm_restore_assignment", omniwm_restore_assignment.self, expected: KernelABISchemaEntry(name: "omniwm_restore_assignment", size: 8, stride: 8, alignment: 4), into: &mismatches)
        check("omniwm_point", omniwm_point.self, expected: KernelABISchemaEntry(name: "omniwm_point", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_rect", omniwm_rect.self, expected: KernelABISchemaEntry(name: "omniwm_rect", size: 32, stride: 32, alignment: 8), into: &mismatches)
        check("omniwm_uuid", omniwm_uuid.self, expected: KernelABISchemaEntry(name: "omniwm_uuid", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_window_token", omniwm_window_token.self, expected: KernelABISchemaEntry(name: "omniwm_window_token", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_logical_window_id", omniwm_logical_window_id.self, expected: KernelABISchemaEntry(name: "omniwm_logical_window_id", size: 8, stride: 8, alignment: 8), into: &mismatches)
        check("omniwm_restore_string_ref", omniwm_restore_string_ref.self, expected: KernelABISchemaEntry(name: "omniwm_restore_string_ref", size: 16, stride: 16, alignment: 8), into: &mismatches)
        check("omniwm_restore_monitor_key", omniwm_restore_monitor_key.self, expected: KernelABISchemaEntry(name: "omniwm_restore_monitor_key", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_restore_monitor_context", omniwm_restore_monitor_context.self, expected: KernelABISchemaEntry(name: "omniwm_restore_monitor_context", size: 112, stride: 112, alignment: 8), into: &mismatches)
        check("omniwm_restore_event_input", omniwm_restore_event_input.self, expected: KernelABISchemaEntry(name: "omniwm_restore_event_input", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_restore_event_output", omniwm_restore_event_output.self, expected: KernelABISchemaEntry(name: "omniwm_restore_event_output", size: 16, stride: 16, alignment: 4), into: &mismatches)
        check("omniwm_restore_visible_workspace_snapshot", omniwm_restore_visible_workspace_snapshot.self, expected: KernelABISchemaEntry(name: "omniwm_restore_visible_workspace_snapshot", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_restore_disconnected_cache_entry", omniwm_restore_disconnected_cache_entry.self, expected: KernelABISchemaEntry(name: "omniwm_restore_disconnected_cache_entry", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_restore_workspace_monitor_fact", omniwm_restore_workspace_monitor_fact.self, expected: KernelABISchemaEntry(name: "omniwm_restore_workspace_monitor_fact", size: 32, stride: 32, alignment: 8), into: &mismatches)
        check("omniwm_restore_topology_input", omniwm_restore_topology_input.self, expected: KernelABISchemaEntry(name: "omniwm_restore_topology_input", size: 144, stride: 144, alignment: 8), into: &mismatches)
        check("omniwm_restore_visible_assignment", omniwm_restore_visible_assignment.self, expected: KernelABISchemaEntry(name: "omniwm_restore_visible_assignment", size: 24, stride: 24, alignment: 8), into: &mismatches)
        check("omniwm_restore_disconnected_cache_output_entry", omniwm_restore_disconnected_cache_output_entry.self, expected: KernelABISchemaEntry(name: "omniwm_restore_disconnected_cache_output_entry", size: 24, stride: 24, alignment: 8), into: &mismatches)
        check("omniwm_restore_topology_output", omniwm_restore_topology_output.self, expected: KernelABISchemaEntry(name: "omniwm_restore_topology_output", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_restore_persisted_key", omniwm_restore_persisted_key.self, expected: KernelABISchemaEntry(name: "omniwm_restore_persisted_key", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_restore_persisted_entry_snapshot", omniwm_restore_persisted_entry_snapshot.self, expected: KernelABISchemaEntry(name: "omniwm_restore_persisted_entry_snapshot", size: 224, stride: 224, alignment: 8), into: &mismatches)
        check("omniwm_restore_persisted_hydration_input", omniwm_restore_persisted_hydration_input.self, expected: KernelABISchemaEntry(name: "omniwm_restore_persisted_hydration_input", size: 152, stride: 152, alignment: 8), into: &mismatches)
        check("omniwm_restore_persisted_hydration_output", omniwm_restore_persisted_hydration_output.self, expected: KernelABISchemaEntry(name: "omniwm_restore_persisted_hydration_output", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_restore_floating_rescue_candidate", omniwm_restore_floating_rescue_candidate.self, expected: KernelABISchemaEntry(name: "omniwm_restore_floating_rescue_candidate", size: 168, stride: 168, alignment: 8), into: &mismatches)
        check("omniwm_restore_floating_rescue_operation", omniwm_restore_floating_rescue_operation.self, expected: KernelABISchemaEntry(name: "omniwm_restore_floating_rescue_operation", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_restore_floating_rescue_output", omniwm_restore_floating_rescue_output.self, expected: KernelABISchemaEntry(name: "omniwm_restore_floating_rescue_output", size: 24, stride: 24, alignment: 8), into: &mismatches)
        check("omniwm_window_decision_rule_summary", omniwm_window_decision_rule_summary.self, expected: KernelABISchemaEntry(name: "omniwm_window_decision_rule_summary", size: 8, stride: 8, alignment: 4), into: &mismatches)
        check("omniwm_window_decision_built_in_rule_summary", omniwm_window_decision_built_in_rule_summary.self, expected: KernelABISchemaEntry(name: "omniwm_window_decision_built_in_rule_summary", size: 12, stride: 12, alignment: 4), into: &mismatches)
        check("omniwm_window_decision_input", omniwm_window_decision_input.self, expected: KernelABISchemaEntry(name: "omniwm_window_decision_input", size: 44, stride: 44, alignment: 4), into: &mismatches)
        check("omniwm_window_decision_output", omniwm_window_decision_output.self, expected: KernelABISchemaEntry(name: "omniwm_window_decision_output", size: 24, stride: 24, alignment: 4), into: &mismatches)
        check("omniwm_workspace_navigation_input", omniwm_workspace_navigation_input.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_navigation_input", size: 256, stride: 256, alignment: 8), into: &mismatches)
        check("omniwm_workspace_navigation_monitor", omniwm_workspace_navigation_monitor.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_navigation_monitor", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_workspace_navigation_workspace", omniwm_workspace_navigation_workspace.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_navigation_workspace", size: 96, stride: 96, alignment: 8), into: &mismatches)
        check("omniwm_workspace_navigation_output", omniwm_workspace_navigation_output.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_navigation_output", size: 184, stride: 184, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_input", omniwm_workspace_session_input.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_input", size: 168, stride: 168, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_monitor", omniwm_workspace_session_monitor.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_monitor", size: 112, stride: 112, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_previous_monitor", omniwm_workspace_session_previous_monitor.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_previous_monitor", size: 112, stride: 112, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_disconnected_cache_entry", omniwm_workspace_session_disconnected_cache_entry.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_disconnected_cache_entry", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_workspace", omniwm_workspace_session_workspace.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_workspace", size: 96, stride: 96, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_window_candidate", omniwm_workspace_session_window_candidate.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_window_candidate", size: 56, stride: 56, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_monitor_result", omniwm_workspace_session_monitor_result.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_monitor_result", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_workspace_projection", omniwm_workspace_session_workspace_projection.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_workspace_projection", size: 32, stride: 32, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_disconnected_cache_result", omniwm_workspace_session_disconnected_cache_result.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_disconnected_cache_result", size: 24, stride: 24, alignment: 8), into: &mismatches)
        check("omniwm_workspace_session_output", omniwm_workspace_session_output.self, expected: KernelABISchemaEntry(name: "omniwm_workspace_session_output", size: 128, stride: 128, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_observed_state", omniwm_reconcile_observed_state.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_observed_state", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_desired_state", omniwm_reconcile_desired_state.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_desired_state", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_floating_state", omniwm_reconcile_floating_state.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_floating_state", size: 56, stride: 56, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_entry", omniwm_reconcile_entry.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_entry", size: 216, stride: 216, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_monitor", omniwm_reconcile_monitor.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_monitor", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_pending_focus", omniwm_reconcile_pending_focus.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_pending_focus", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_focus_session", omniwm_reconcile_focus_session.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_focus_session", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_persisted_hydration", omniwm_reconcile_persisted_hydration.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_persisted_hydration", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_event", omniwm_reconcile_event.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_event", size: 136, stride: 136, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_restore_intent_output", omniwm_reconcile_restore_intent_output.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_restore_intent_output", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_replacement_correlation", omniwm_reconcile_replacement_correlation.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_replacement_correlation", size: 40, stride: 40, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_focus_session_output", omniwm_reconcile_focus_session_output.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_focus_session_output", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_reconcile_plan_output", omniwm_reconcile_plan_output.self, expected: KernelABISchemaEntry(name: "omniwm_reconcile_plan_output", size: 336, stride: 336, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_old_frame_record", omniwm_orchestration_old_frame_record.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_old_frame_record", size: 48, stride: 48, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_window_removal_payload", omniwm_orchestration_window_removal_payload.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_window_removal_payload", size: 72, stride: 72, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_follow_up_refresh", omniwm_orchestration_follow_up_refresh.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_follow_up_refresh", size: 24, stride: 24, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_refresh", omniwm_orchestration_refresh.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_refresh", size: 96, stride: 96, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_managed_request", omniwm_orchestration_managed_request.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_managed_request", size: 56, stride: 56, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_refresh_snapshot", omniwm_orchestration_refresh_snapshot.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_refresh_snapshot", size: 200, stride: 200, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_focus_snapshot", omniwm_orchestration_focus_snapshot.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_focus_snapshot", size: 104, stride: 104, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_snapshot", omniwm_orchestration_snapshot.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_snapshot", size: 304, stride: 304, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_refresh_request_event", omniwm_orchestration_refresh_request_event.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_refresh_request_event", size: 104, stride: 104, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_refresh_completion_event", omniwm_orchestration_refresh_completion_event.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_refresh_completion_event", size: 104, stride: 104, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_focus_request_event", omniwm_orchestration_focus_request_event.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_focus_request_event", size: 32, stride: 32, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_activation_observation", omniwm_orchestration_activation_observation.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_activation_observation", size: 64, stride: 64, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_event", omniwm_orchestration_event.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_event", size: 312, stride: 312, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_decision", omniwm_orchestration_decision.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_decision", size: 80, stride: 80, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_action", omniwm_orchestration_action.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_action", size: 104, stride: 104, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_step_input", omniwm_orchestration_step_input.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_step_input", size: 680, stride: 680, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_step_output", omniwm_orchestration_step_output.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_step_output", size: 528, stride: 528, alignment: 8), into: &mismatches)
        check("omniwm_orchestration_abi_layout_info", omniwm_orchestration_abi_layout_info.self, expected: KernelABISchemaEntry(name: "omniwm_orchestration_abi_layout_info", size: 176, stride: 176, alignment: 8), into: &mismatches)
        return mismatches
    }

    private static func check<T>(
        _ name: String,
        _ type: T.Type,
        expected: KernelABISchemaEntry,
        into mismatches: inout [Mismatch]
    ) {
        let actual = KernelABISchemaEntry(
            name: name,
            size: MemoryLayout<T>.size,
            stride: MemoryLayout<T>.stride,
            alignment: MemoryLayout<T>.alignment
        )
        if actual != expected {
            mismatches.append(Mismatch(name: name, expected: expected, actual: actual))
        }
    }
}
