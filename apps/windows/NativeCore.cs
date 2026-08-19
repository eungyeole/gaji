using System.Runtime.InteropServices;
using System.Text.Json;

namespace Rift.Windows;

internal static class NativeCore
{
    private static readonly JsonSerializerOptions JsonOptions = new() {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_inspect_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_execute_json([MarshalAs(UnmanagedType.LPUTF8Str)] string request);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_commit_graph_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path, nuint limit);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_blame_json(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string file);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_worktrees_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_submodules_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_stashes_json([MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint rift_file_hunks_json(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string file,
        [MarshalAs(UnmanagedType.I1)] bool staged);

    [DllImport("rift_ffi", CallingConvention = CallingConvention.Cdecl)]
    private static extern void rift_string_free(nint value);

    public static CoreSnapshot Inspect(string path) => Decode<CoreSnapshot>(rift_inspect_json(path));
    public static CoreGraphCommit[] Graph(string path, nuint limit = 500) =>
        Decode<CoreGraphCommit[]>(rift_commit_graph_json(path, limit));
    public static CoreBlameLine[] Blame(string path, string file) =>
        Decode<CoreBlameLine[]>(rift_blame_json(path, file));
    public static CoreWorktree[] Worktrees(string path) => Decode<CoreWorktree[]>(rift_worktrees_json(path));
    public static CoreSubmodule[] Submodules(string path) => Decode<CoreSubmodule[]>(rift_submodules_json(path));
    public static CoreStash[] Stashes(string path) => Decode<CoreStash[]>(rift_stashes_json(path));
    public static CoreDiffHunk[] Hunks(string path, string file, bool staged) =>
        Decode<CoreDiffHunk[]>(rift_file_hunks_json(path, file, staged));

    public static void Execute(object request)
    {
        var json = JsonSerializer.Serialize(request, JsonOptions);
        var envelope = DecodeEnvelope<JsonElement>(rift_execute_json(json));
        if (!envelope.Ok) throw new InvalidOperationException(envelope.Error ?? "Git operation failed");
    }

    private static T Decode<T>(nint pointer)
    {
        var envelope = DecodeEnvelope<T>(pointer);
        if (!envelope.Ok || envelope.Value is null)
            throw new InvalidOperationException(envelope.Error ?? "Native core failed");
        return envelope.Value;
    }

    private static CoreEnvelope<T> DecodeEnvelope<T>(nint pointer)
    {
        if (pointer == 0) throw new InvalidOperationException("Native core returned no response");
        try
        {
            var json = Marshal.PtrToStringUTF8(pointer) ?? throw new InvalidOperationException("Invalid native response");
            return JsonSerializer.Deserialize<CoreEnvelope<T>>(json, JsonOptions)
                ?? throw new InvalidOperationException("Could not decode native response");
        }
        finally { rift_string_free(pointer); }
    }
}

internal sealed record CoreEnvelope<T>(bool Ok, T? Value, string? Error);
internal sealed record CoreSnapshot(string Root, string Branch, CoreChange[] Changes, CoreCommit[] RecentCommits);
internal sealed record CoreChange(string IndexStatus, string WorktreeStatus, string Path);
internal sealed record CoreCommit(string Id, string Author, string AuthoredAt, string Subject);
internal sealed record CoreGraphCommit(
    string Id, string[] Parents, string[] References, string Author, string AuthoredAt, string Subject);
internal sealed record CoreBlameLine(int LineNumber, string Commit, string Author, long AuthoredAt, string Content);
internal sealed record CoreWorktree(string Path, string Commit, string? Branch, bool IsBare);
internal sealed record CoreSubmodule(string Path, string Commit, char State);
internal sealed record CoreStash(int Index, string Reference, string Subject);
internal sealed record CoreDiffHunk(int Id, string Header, string Patch);
