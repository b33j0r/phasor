const example_shared = @import("example_shared");

const shared_loading = example_shared.loading;
const shared_assets_loading = example_shared.assets_loading;

pub const Model = shared_loading.Model;
pub const StatusText = shared_loading.StatusText;
pub const BarTrack = shared_loading.BarTrack;
pub const BarFill = shared_loading.BarFill;

pub const setup = shared_loading.setup;
pub const sync = shared_loading.sync;

pub fn AssetLoading(comptime AssetsT: type) type {
    return shared_assets_loading.AssetLoading(AssetsT);
}
