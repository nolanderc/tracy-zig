fn currentDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

fn globalOption(comptime name: []const u8, comptime T: type) ?T {
    const root = @import("root");
    if (@hasDecl(root, name)) return @field(root, name);
    return null;
}

pub const enabled = globalOption("tracy_enabled", bool) orelse true;
const callstack_enabled = globalOption("tracy_capture_callstacks", bool) orelse false;

const c = if (enabled)
    @cImport({
        @cDefine("TRACY_ENABLE", {});
        @cDefine(if (callstack_enabled) "TRACY_CALLSTACK" else "TRACY_NO_CALLSTACK", {});
        @cInclude(currentDir() ++ "/public/tracy/TracyC.h");
    })
else
    struct {};

const std = @import("std");

const has_callstack = @hasDecl(c, "TRACY_HAS_CALLSTACK");
const callstack_depth = globalOption("tracy_callstack_depth", c_int) orelse 16;
const capture_callstack = callstack_enabled and has_callstack and callstack_depth > 0;

pub fn setThreadName(name: [*:0]const u8) void {
    if (enabled) c.___tracy_set_thread_name(name);
}

pub inline fn endFrame() void {
    if (enabled) c.___tracy_emit_frame_mark(null);
}

pub const Zone = struct {
    ctx: if (enabled) c.TracyCZoneCtx else void,

    pub fn end(self: @This()) void {
        if (enabled) c.___tracy_emit_zone_end(self.ctx);
    }
};

pub const Color = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    a: u8 = 255,
};

pub inline fn zone(comptime src: std.builtin.SourceLocation, name: ?[*:0]const u8) Zone {
    return zoneColor(src, name, std.mem.zeroes(Color));
}

pub inline fn zoneColor(
    comptime src: std.builtin.SourceLocation,
    name: ?[*:0]const u8,
    color: Color,
) Zone {
    if (!enabled) return .{ .ctx = {} };

    const static = struct {
        var loc: c.___tracy_source_location_data = undefined;
    };
    static.loc = .{
        .name = name,
        .function = src.fn_name.ptr,
        .file = src.file.ptr,
        .line = src.line,
        .color = @bitCast(color),
    };

    const zone_ctx = c.___tracy_emit_zone_begin(&static.loc, 1);

    return .{ .ctx = zone_ctx };
}

pub const TracyAllocator = struct {
    backing: std.mem.Allocator,

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn selfCast(ctx: *anyopaque) *@This() {
        return @ptrCast(@alignCast(ctx));
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self = selfCast(ctx);
        const ptr = self.backing.rawAlloc(len, ptr_align, ret_addr);
        traceAlloc(ptr, len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self = selfCast(ctx);
        const result = self.backing.rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            traceFree(buf.ptr);
            traceAlloc(buf.ptr, new_len);
        }
        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self = selfCast(ctx);
        self.backing.rawFree(buf, buf_align, ret_addr);
        traceFree(buf.ptr);
    }
};

pub fn wrapAllocator(backing: std.mem.Allocator) TracyAllocator {
    return .{ .backing = backing };
}

pub inline fn traceAlloc(ptr: [*c]u8, size: usize) void {
    if (!enabled) return;
    if (capture_callstack) {
        c.___tracy_emit_memory_alloc_callstack(ptr, size, callstack_depth, 0);
    } else {
        c.___tracy_emit_memory_alloc(ptr, size, 0);
    }
}

pub inline fn traceFree(ptr: [*c]u8) void {
    if (!enabled) return;
    if (capture_callstack) {
        c.___tracy_emit_memory_free_callstack(ptr, callstack_depth, 0);
    } else {
        c.___tracy_emit_memory_free(ptr, 0);
    }
}
