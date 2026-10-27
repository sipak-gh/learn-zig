//! Command-line options and a flag parser generated at compile time.
//!
//! `parse` and `help` work for any struct type whose fields all have default
//! values. Each field becomes a long flag (`ignore_case` -> `--ignore-case`);
//! a `shorts` declaration adds one-letter aliases and a `descriptions`
//! declaration provides the help text.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// When to highlight matches.
pub const Color = enum { auto, always, never };

/// Everything the user can configure. Every field has a default, so `.{}`
/// is a complete value. Adding a field here adds a flag to seek.
pub const Options = struct {
    ignore_case: bool = false,
    invert: bool = false,
    line_numbers: bool = false,
    count_only: bool = false,
    files_only: bool = false,
    max_count: ?usize = null,
    hidden: bool = false,
    glob: ?[]const u8 = null,
    color: Color = .auto,
    stats: bool = false,
    help: bool = false,
    version: bool = false,

    /// One-letter aliases. An anonymous struct literal is a handy
    /// compile-time "map" from field name to value.
    pub const shorts = .{
        .ignore_case = 'i',
        .invert = 'v',
        .line_numbers = 'n',
        .count_only = 'c',
        .files_only = 'l',
        .max_count = 'm',
        .help = 'h',
    };

    pub const descriptions = .{
        .ignore_case = "ignore case when matching",
        .invert = "select lines that do NOT match",
        .line_numbers = "print line numbers",
        .count_only = "print only a count of selected lines per file",
        .files_only = "print only names of files with selected lines",
        .max_count = "stop after N selected lines per file",
        .hidden = "search hidden files and directories",
        .glob = "only search files whose name matches GLOB (* and ?)",
        .color = "highlight matches",
        .stats = "print statistics to stderr when done",
        .help = "show this help",
        .version = "show the version",
    };
};

pub const Error = error{ UnknownFlag, MissingValue, InvalidValue };

/// Filled in by `parse` to tell the caller which argument was wrong.
pub const Diagnostic = struct {
    flag: []const u8 = "",
    value: []const u8 = "",
};

/// Parses `args` (without the program name) into a `T`. Flags and
/// positional arguments may be mixed; everything after `--` is positional.
/// Returns the options and the positional arguments; the latter is
/// allocated with `gpa` and owned by the caller.
pub fn parse(
    comptime T: type,
    gpa: Allocator,
    args: []const [:0]const u8,
    diag: *Diagnostic,
) (Error || Allocator.Error)!struct { T, []const []const u8 } {
    // These checks run while compiling; a typo in `shorts` is a compile error.
    comptime validate(T);
    const fields = @typeInfo(T).@"struct";

    var options: T = .{};
    var positionals: std.ArrayList([]const u8) = .empty;
    errdefer positionals.deinit(gpa);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            for (args[i + 1 ..]) |rest| try positionals.append(gpa, rest);
            break;
        }
        // "-" alone is a PATH (standard input), not a flag.
        if (arg.len < 2 or arg[0] != '-') {
            try positionals.append(gpa, arg);
            continue;
        }

        // Accept both `--color always` and `--color=always`.
        const flag, const attached_value: ?[]const u8 = if (std.mem.cutScalar(u8, arg, '=')) |parts|
            .{ parts[0], parts[1] }
        else
            .{ arg, null };
        diag.* = .{ .flag = flag };

        // `inline for` unrolls the loop at compile time: one copy of the
        // body per field, each with its own comptime-known name and type.
        const known = inline for (fields.field_names, fields.field_types) |name, FieldType| {
            if (isFlag(T, name, flag)) {
                if (FieldType == bool) {
                    // A switch takes no value: `--hidden=yes` is a mistake.
                    if (attached_value) |value| {
                        diag.value = value;
                        return error.InvalidValue;
                    }
                    @field(options, name) = true;
                } else {
                    const value = attached_value orelse blk: {
                        i += 1;
                        if (i == args.len) return error.MissingValue;
                        break :blk args[i];
                    };
                    diag.value = value;
                    @field(options, name) = try parseValue(FieldType, value);
                }
                break true;
            }
        } else false;
        if (!known) return error.UnknownFlag;
    }
    return .{ options, try positionals.toOwnedSlice(gpa) };
}

/// Reports whether `flag` (like "-i" or "--ignore-case") names field `name`.
fn isFlag(comptime T: type, comptime name: []const u8, flag: []const u8) bool {
    if (std.mem.cutPrefix(u8, flag, "--")) |long| {
        return std.mem.eql(u8, long, comptime kebab(name));
    }
    if (@hasField(@TypeOf(T.shorts), name)) {
        const short: u8 = @field(T.shorts, name);
        return flag.len == 2 and flag[1] == short;
    }
    return false;
}

/// Converts the text of a flag's value to the field's type.
fn parseValue(comptime V: type, text: []const u8) error{InvalidValue}!V {
    return switch (@typeInfo(V)) {
        .int => std.fmt.parseInt(V, text, 10) catch error.InvalidValue,
        .@"enum" => std.meta.stringToEnum(V, text) orelse error.InvalidValue,
        .optional => |optional| try parseValue(optional.child, text),
        .pointer => if (V == []const u8) text else unsupported(V),
        else => unsupported(V),
    };
}

fn unsupported(comptime V: type) noreturn {
    @compileError("cli: unsupported option type " ++ @typeName(V));
}

/// "ignore_case" -> "ignore-case", computed at compile time.
fn kebab(comptime name: []const u8) []const u8 {
    comptime {
        var buffer: [name.len]u8 = name[0..name.len].*;
        std.mem.replaceScalar(u8, &buffer, '_', '-');
        // Copy into a constant so the result can outlive this block.
        const result = buffer;
        return &result;
    }
}

/// The placeholder shown after a flag in the help text: nothing for a
/// bool, `N` for a number, the choices for an enum, and the field name in
/// upper case for a string.
fn valueName(comptime V: type, comptime name: []const u8) []const u8 {
    comptime {
        return switch (@typeInfo(V)) {
            .bool => "",
            .int => " N",
            .optional => |optional| valueName(optional.child, name),
            .@"enum" => |info| blk: {
                var choices: []const u8 = " ";
                for (info.field_names, 0..) |choice, i| {
                    choices = choices ++ (if (i > 0) "|" else "") ++ choice;
                }
                break :blk choices;
            },
            else => blk: {
                var upper: [name.len]u8 = undefined;
                _ = std.ascii.upperString(&upper, name);
                const result = upper;
                break :blk " " ++ &result;
            },
        };
    }
}

/// Builds the option list for `--help` from the fields of `T`. All of it
/// happens at compile time; the program only contains the finished string.
pub fn help(comptime T: type) []const u8 {
    comptime {
        validate(T);
        var text: []const u8 = "";
        const fields = @typeInfo(T).@"struct";
        for (fields.field_names, fields.field_types) |name, FieldType| {
            const short = if (@hasField(@TypeOf(T.shorts), name))
                std.fmt.comptimePrint("-{c}, ", .{@field(T.shorts, name)})
            else
                "    ";
            const long = "--" ++ kebab(name) ++ valueName(FieldType, name);
            text = text ++ std.fmt.comptimePrint("  {s}{s:<26} {s}\n", .{
                short,
                long,
                @field(T.descriptions, name),
            });
        }
        return text;
    }
}

/// Compile-time checks that turn mistakes into readable compile errors.
fn validate(comptime T: type) void {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("cli: expected a struct, found " ++ @typeName(T));
    for (info.@"struct".field_names, info.@"struct".field_attrs) |name, attrs| {
        if (attrs.default_value_ptr == null) @compileError("cli: field '" ++ name ++ "' needs a default value");
        if (!@hasField(@TypeOf(T.descriptions), name)) @compileError("cli: field '" ++ name ++ "' needs a description");
    }
    for (@typeInfo(@TypeOf(T.shorts)).@"struct".field_names) |name| {
        if (!@hasField(T, name)) @compileError("cli: shorts." ++ name ++ " is not a field of " ++ @typeName(T));
    }
}
