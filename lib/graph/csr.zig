pub fn Graph(comptime N: type, comptime E: type) type {
    return struct {
        allocator: std.mem.Allocator,
        nodes: std.ArrayListUnmanaged(N) = .empty,
        edges: std.ArrayListUnmanaged(EdgeInput) = .empty,
        csr_edge_targets: []usize = &[_]usize{},
        csr_edges: []E = &[_]E{},
        csr_offsets: []usize = &[_]usize{},
        csr_valid: bool = false,
        csr_allocated: bool = false,
        version: u64 = 0,

        const Self = @This();

        pub const Error = error{
            InvalidNodeIndex,
            CycleDetected,
        };

        pub const EdgeSlice = struct {
            targets: []const usize,
            data: []const E,

            pub fn len(self: EdgeSlice) usize {
                return self.targets.len;
            }
        };

        pub const EdgeInput = struct {
            from: usize,
            to: usize,
            data: E,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit(self.allocator);
            self.edges.deinit(self.allocator);
            self.clearCsr();
            self.* = undefined;
        }

        pub fn addNode(self: *Self, value: N) !usize {
            const index = self.nodes.items.len;
            try self.nodes.append(self.allocator, value);
            self.markDirty();
            return index;
        }

        pub fn addEdge(self: *Self, from: usize, to: usize, data: E) !void {
            if (from >= self.nodes.items.len or to >= self.nodes.items.len) {
                return Error.InvalidNodeIndex;
            }
            try self.edges.append(self.allocator, .{ .from = from, .to = to, .data = data });
            self.markDirty();
        }

        pub fn nodeCount(self: *const Self) usize {
            return self.nodes.items.len;
        }

        pub fn edgeCount(self: *const Self) usize {
            return self.edges.items.len;
        }

        pub fn versionId(self: *const Self) u64 {
            return self.version;
        }

        pub fn node(self: *const Self, index: usize) *const N {
            std.debug.assert(index < self.nodes.items.len);
            return &self.nodes.items[index];
        }

        pub fn edgesFrom(self: *Self, node_index: usize) !EdgeSlice {
            std.debug.assert(node_index < self.nodes.items.len);
            try self.ensureCsr();
            const start = self.csr_offsets[node_index];
            const end = self.csr_offsets[node_index + 1];
            return .{
                .targets = self.csr_edge_targets[start..end],
                .data = self.csr_edges[start..end],
            };
        }

        pub fn topologicalOrder(self: *Self, allocator: std.mem.Allocator) ![]usize {
            const node_count = self.nodes.items.len;
            if (node_count == 0) {
                return allocator.alloc(usize, 0);
            }

            try self.ensureCsr();

            var indegree = try allocator.alloc(usize, node_count);
            defer allocator.free(indegree);
            @memset(indegree, 0);

            for (self.csr_edge_targets) |target| {
                std.debug.assert(target < node_count);
                indegree[target] += 1;
            }

            var queue: std.ArrayListUnmanaged(usize) = .empty;
            defer queue.deinit(allocator);

            for (indegree, 0..) |count, index| {
                if (count == 0) {
                    try queue.append(allocator, index);
                }
            }

            const order = try allocator.alloc(usize, node_count);
            var head: usize = 0;
            var out_index: usize = 0;

            while (head < queue.items.len) : (head += 1) {
                const node_index = queue.items[head];
                order[out_index] = node_index;
                out_index += 1;

                const edge_slice = try self.edgesFrom(node_index);
                for (edge_slice.targets) |target| {
                    indegree[target] -= 1;
                    if (indegree[target] == 0) {
                        try queue.append(allocator, target);
                    }
                }
            }

            if (out_index != node_count) {
                allocator.free(order);
                return Error.CycleDetected;
            }

            return order;
        }

        fn markDirty(self: *Self) void {
            self.version += 1;
            self.csr_valid = false;
        }

        fn clearCsr(self: *Self) void {
            if (self.csr_allocated) {
                self.allocator.free(self.csr_edge_targets);
                self.allocator.free(self.csr_edges);
                self.allocator.free(self.csr_offsets);
            }
            self.csr_edge_targets = &[_]usize{};
            self.csr_edges = &[_]E{};
            self.csr_offsets = &[_]usize{};
            self.csr_valid = false;
            self.csr_allocated = false;
        }

        fn ensureCsr(self: *Self) !void {
            if (self.csr_valid) return;

            self.clearCsr();

            const node_count = self.nodes.items.len;
            const edge_count = self.edges.items.len;

            self.csr_edge_targets = try self.allocator.alloc(usize, edge_count);
            self.csr_edges = try self.allocator.alloc(E, edge_count);
            self.csr_offsets = try self.allocator.alloc(usize, node_count + 1);
            self.csr_allocated = true;

            @memset(self.csr_offsets, 0);

            var counts = try self.allocator.alloc(usize, node_count);
            defer self.allocator.free(counts);
            @memset(counts, 0);

            for (self.edges.items) |edge| {
                counts[edge.from] += 1;
            }

            self.csr_offsets[0] = 0;
            var i: usize = 0;
            while (i < node_count) : (i += 1) {
                self.csr_offsets[i + 1] = self.csr_offsets[i] + counts[i];
            }

            var cursor = try self.allocator.alloc(usize, node_count);
            defer self.allocator.free(cursor);
            @memcpy(cursor, self.csr_offsets[0..node_count]);

            for (self.edges.items) |edge| {
                const index = cursor[edge.from];
                self.csr_edge_targets[index] = edge.to;
                self.csr_edges[index] = edge.data;
                cursor[edge.from] += 1;
            }

            self.csr_valid = true;
        }
    };
}

// Imports
const std = @import("std");

test "csr graph build and order" {
    const allocator = std.testing.allocator;
    var graph = Graph(u8, u8).init(allocator);
    defer graph.deinit();

    _ = try graph.addNode(1);
    _ = try graph.addNode(2);
    _ = try graph.addNode(3);
    try graph.addEdge(0, 1, 10);
    try graph.addEdge(1, 2, 20);

    try std.testing.expectEqual(@as(usize, 3), graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 2), graph.edgeCount());
    try std.testing.expectEqual(@as(u64, 5), graph.versionId());

    const edge0 = try graph.edgesFrom(0);
    try std.testing.expectEqual(@as(usize, 1), edge0.len());
    try std.testing.expectEqual(@as(usize, 1), edge0.targets[0]);
    try std.testing.expectEqual(@as(u8, 10), edge0.data[0]);

    const order = try graph.topologicalOrder(allocator);
    defer allocator.free(order);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, order);
}

test "csr graph detects cycle" {
    const allocator = std.testing.allocator;
    var graph = Graph(u8, void).init(allocator);
    defer graph.deinit();

    _ = try graph.addNode(1);
    _ = try graph.addNode(2);
    try graph.addEdge(0, 1, {});
    try graph.addEdge(1, 0, {});

    try std.testing.expectError(Graph(u8, void).Error.CycleDetected, graph.topologicalOrder(allocator));
}
