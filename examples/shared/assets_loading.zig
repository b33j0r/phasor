const std = @import("std");
const phasor = @import("phasor");
const loading = @import("loading.zig");

pub fn AssetLoading(comptime AssetsT: type) type {
    return struct {
        pub const State = phasor.AssetsLoadState(AssetsT);

        pub fn begin(commands: *Commands, loader: ResMut(State)) void {
            loader.ptr.beginDefaultSession(commands.io);
        }

        pub fn restart(commands: *Commands, loader: ResMut(State)) void {
            loader.ptr.beginDefaultSession(commands.io);
        }

        pub fn sync(
            events: EventReader(AssetsProgressEvent),
            loader: Res(State),
            ui: ResMut(loading.Model),
        ) !void {
            while (events.next()) |event| {
                ui.ptr.progress01 = event.progress01;
                if (event.asset_name) |name| {
                    const counts = loader.ptr.currentCounts();
                    const percent: usize = @intFromFloat(event.progress01 * 100.0);
                    try ui.ptr.setStatusFmt(
                        "{s} {s}\n{d}% complete ({d}/{d})",
                        .{
                            stageLabel(event.stage),
                            std.fs.path.basename(name),
                            percent,
                            counts.completed,
                            counts.total,
                        },
                    );
                }
            }

            ui.ptr.visible = !loader.ptr.isComplete();
            ui.ptr.progress01 = loader.ptr.overallProgress01();
            if (!ui.ptr.visible) ui.ptr.clearStatus();
        }
    };
}

fn stageLabel(stage: AssetsLoadStage) []const u8 {
    return switch (stage) {
        .idle => "idle",
        .bundle_started => "Starting",
        .bundle_planning => "Planning",
        .bundle_plan_complete => "Planned",
        .bundle_executing => "Loading",
        .asset_discovered => "Found",
        .asset_planned => "Planned",
        .asset_execute => "Loading",
        .scene_prepared => "Prepared",
        .scene_instance_gpu_started => "Uploading",
        .scene_instance_gpu_progress => "Uploading",
        .asset_complete => "Loaded",
        .bundle_complete => "Ready",
    };
}

const AssetsLoadStage = phasor.AssetsLoadStage;
const AssetsProgressEvent = phasor.AssetsProgressEvent;
const Commands = phasor.Commands;
const EventReader = phasor.EventReader;
const Res = phasor.Res;
const ResMut = phasor.ResMut;
